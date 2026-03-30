# Session Learnings: Cloudflare Workers Infrastructure Build-out

Technical knowledge, pitfalls, and methodology captured during the initial build-out of the `match` service, `file-server` refactor, and architecture review. This document covers what we learned *building* these services — for usage and configuration, see each module's README.

---

## 1. Problems Encountered

### P1: Private repo `browser_download_url` returns 404

**Symptom:** `curl match.sshawn9.com/control-x86` returned `Download failed: 404 Not Found`, even though the release asset clearly existed on GitHub (visible in the web UI).

**What we tried first (wrong):** The GitHub Releases API (`GET /repos/{owner}/{repo}/releases/latest`) returns a `browser_download_url` field for each asset. We used this URL directly with an `Authorization: token <PAT>` header. This works for **public** repos but returns **404 for private repos** — even with a valid token.

**Root cause:** `browser_download_url` points to `github.com/{owner}/{repo}/releases/download/{tag}/{filename}`, which goes through GitHub's web download flow. This flow uses cookie-based session auth and does not honor API bearer tokens. For private repos, the request is treated as unauthenticated and returns 404.

**Fix:** Use the GitHub API asset endpoint instead:

```
GET https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}
Accept: application/octet-stream
Authorization: token <PAT>
```

This returns a **302 redirect** to a temporary signed S3 URL. Following the redirect downloads the file. The signed URL works without additional auth headers and expires after a short period.

**Key code change** (`match/worker/src/index.ts`):
```typescript
// Before (broken for private repos):
return { url: asset.browser_download_url, fileName: asset.name };

// After (works for both public and private):
const assetApiUrl = `https://api.github.com/repos/${repo}/releases/assets/${asset.id}`;
return { assetApiUrl, fileName: asset.name };
// Then fetch with: Accept: application/octet-stream
```

**Takeaway:** When building anything that downloads GitHub release assets, decide early whether private repos must be supported. If yes, always use the API asset endpoint (`/releases/assets/{id}` + `Accept: application/octet-stream`), never `browser_download_url`. This is the kind of bug that works perfectly in testing with public repos and breaks silently in production with private ones.

---

### P2: 2D keyword array AND/OR semantics misconfigured — wrong architecture downloaded

**Symptom:** `curl match.sshawn9.com/control-x86` downloaded `motion_control_jammy_aarch64_2.0.5.deb` (ARM) instead of the x86 version.

**Root cause:** The `asset_keywords` in `rules.json` were written as:

```json
"asset_keywords": [["motion_control", "x86", ".deb"]]
```

This is **one inner array** = **one OR group**, meaning: match if filename contains `motion_control` **OR** `x86` **OR** `.deb`. Since every asset in the `motion_control` repo contains `motion_control` in its name, the **first asset** (aarch64) matched immediately — the `x86` keyword was never required.

**What it should have been:**

```json
"asset_keywords": [["motion_control"], ["x86"], [".deb"]]
```

This is **three inner arrays** = **three AND groups**, meaning: match if filename contains `motion_control` **AND** `x86` **AND** `.deb`. Now only the x86 deb file matches.

**Visual comparison:**

```
WRONG: [["a", "b", "c"]]     → contains(a) OR contains(b) OR contains(c)
RIGHT: [["a"], ["b"], ["c"]]  → contains(a) AND contains(b) AND contains(c)
MIXED: [["a", "b"], ["c"]]   → (contains(a) OR contains(b)) AND contains(c)
```

**Why this was confusing:** The 2D array syntax is compact but the nesting semantics are counterintuitive. Outer = AND, inner = OR is the opposite of what many people expect. The same pattern is used for both `keywords` (URL path matching) and `asset_keywords` (filename matching), compounding the risk since an error in one won't necessarily surface the same way in the other.

**Takeaway:** When using the 2D AND/OR array pattern, always test with inputs that share partial keywords. If your test cases all have completely unique keywords, you won't catch OR-vs-AND confusion. In this case, testing with an asset list where multiple files shared the `motion_control` prefix immediately revealed the bug.

---

### P3: Cache key collision after subdomain-to-path routing refactor

**Symptom:** Caught during design review, not hit in production. Would have caused all file-server paths to return the same cached file.

**Root cause:** The original file-server used subdomain-based routing (`iet.sshawn9.com`, `deploy-easytier-web.sshawn9.com`). The cache key was:

```typescript
const cacheKey = new Request(url.origin);
// url.origin = "https://iet.sshawn9.com" or "https://deploy-easytier-web.sshawn9.com"
// Different subdomains → different origins → different cache keys ✓
```

After refactoring to path-based routing (`file.sshawn9.com/iet`, `file.sshawn9.com/deploy-easytier-web`):

```typescript
const cacheKey = new Request(url.origin);
// url.origin = "https://file.sshawn9.com" for ALL paths
// Same origin → same cache key → first response cached for all paths ✗
```

**Fix:**

```typescript
const cacheKey = new Request(`${url.origin}${url.pathname}`);
// "https://file.sshawn9.com/iet" vs "https://file.sshawn9.com/deploy-easytier-web"
// Different paths → different cache keys ✓
```

**Takeaway:** When refactoring URL schemes, audit every code path that depends on URL structure: routing, caching, logging, error messages, CORS. Cache keys are the easiest to miss because they silently serve stale/wrong data rather than failing loudly. The implicit uniqueness you relied on (hostname, in this case) may no longer hold after the refactor.

---

## 2. Technical Insights

### GitHub API rate limits with PAT

- **Authenticated (PAT):** 5,000 requests/hour, tracked **per token** (not per IP)
- **Unauthenticated:** 60 requests/hour, tracked **per IP**
- If your Worker is hitting rate limits despite having a `GITHUB_TOKEN` configured, the token is likely not being sent — check that the Cloudflare Worker secret is set correctly (`wrangler secret put GITHUB_TOKEN`)
- Cloudflare edge caching (`s-maxage`) dramatically reduces actual API usage: 2 API calls per cache miss (1 for release metadata, 1 for asset download), 0 per cache hit

### Cloudflare Workers custom_domain auto-manages DNS

Worker `custom_domain` entries in `wrangler.toml` automatically create and manage DNS records in Cloudflare. You do **not** need to add these domains to Terraform `cf-dns/`. Manually creating a DNS record for a Worker custom domain will cause conflicts.

### Bundled config vs runtime-fetched config

| Approach | Pros | Cons | Used by |
|----------|------|------|---------|
| Bundled (`import x from './rules.json'`) | No API call, no cache logic, faster cold start | Requires redeploy on config change | match (rules.json) |
| Runtime fetch (GitHub raw content API) | Config changes take effect without redeploy (after cache expires) | Extra API call per cache miss, needs cache management | file-server (routes.json, shared/*.conf) |

When bundling, ensure your CI/CD path trigger covers the config file's location. match uses `match/**` (not `match/worker/**`) specifically so that changes to `rules.json` inside `worker/src/` trigger a redeploy.

### GitHub API asset download flow (private repos)

```
Client → GET /repos/{owner}/{repo}/releases/assets/{id}
         Accept: application/octet-stream
         Authorization: token <PAT>
     ← 302 Location: https://objects.githubusercontent.com/...?token=signed_token
Client → GET (signed URL, no auth header needed)
     ← 200 (binary content)
```

The signed URL is temporary (expires in minutes) and includes the auth in the URL itself. When using Cloudflare Workers, `fetch()` with `redirect: "follow"` handles this transparently.

### Cloudflare edge cache per-PoP behavior

`s-maxage` caching happens independently at each Cloudflare Point of Presence (PoP). Users hitting different PoPs may see different cache states. This means:
- A new release won't be visible everywhere simultaneously — it propagates as each PoP's cache expires
- `?nocache` bypass is useful for debugging (dl-proxy has this, match does not yet)

---

## 3. Methodology & Mental Models

### "They all serve files" is a superficial similarity

When reviewing three services that all "serve files" (file-server, dl-proxy, match), the instinct is to merge them. The architecture decision was to keep them separate, based on analyzing the **actual differences** rather than surface similarities:

| Dimension | file-server | dl-proxy | match |
|-----------|-------------|----------|-------|
| Routing | name → local file | full URL → external proxy | keywords → latest release asset |
| Data source | Repo files (GitHub raw) | Any whitelisted domain | GitHub Releases API |
| Processing | Template injection ({{KEY}} replacement) | Pass-through | None |
| Auth | None (public) | Token required | None (public) |
| Cache TTL | 5 min (content changes with git push) | 1 hour (versioned URLs) | 1 hour (latest release) |

Merging would require a routing dispatch layer (subdomain or path prefix to determine behavior), shared but divergent config formats, and conditional logic throughout. The Cloudflare Workers model (one Worker per custom domain, independently deployed) naturally fits independent services.

**Mental model:** When evaluating "should we merge X and Y", list the dimensions that actually differ (routing, data source, auth, processing, caching). If most dimensions differ, merging adds a dispatch layer with no offsetting simplification.

### 2D array AND/OR as a reusable pattern

The `keywords: string[][]` pattern (outer = AND, inner = OR) is simple to implement and surprisingly versatile:

```typescript
function matches(input: string, keywords: string[][]): boolean {
  return keywords.every(group => group.some(kw => input.includes(kw)));
}
```

Used for:
- URL path matching (`keywords` field — does the user's request match this rule?)
- Asset filename matching (`asset_keywords` field — does this release asset match what we want?)

The same 5-line function handles both. First-match-wins ordering gives implicit priority without needing explicit priority fields.

### Audit all URL-dependent code paths during routing refactors

When changing a URL scheme (subdomain → path, path prefix changes, etc.), systematically check:
- **Routing logic** (obvious — this is what you're changing)
- **Cache keys** (subtle — often derived from URL components)
- **Error messages** (cosmetic but confusing if they reference the old scheme)
- **CORS / security headers** (may reference specific origins)
- **External references** (scripts, docs, bookmarks that use the old URLs)

### Test with overlapping inputs

When building any matching/routing system, always include test cases where inputs **partially overlap** with multiple rules. Pure unique-keyword tests won't catch AND/OR confusion, priority ordering bugs, or overly broad patterns.

---

## 4. Open Questions / Future Work

- **No `?nocache` on match service:** dl-proxy supports `?nocache` to bypass edge cache. match service doesn't have this yet. Useful for debugging when a new release is published and you want to verify it's picked up immediately without waiting for cache expiry.

- **file-server runtime config freshness:** Changes to `routes.json`, `files/`, or `shared/*.conf` don't trigger a Worker redeploy (by design — they're fetched from GitHub at runtime). Freshness depends solely on the 5-minute cache TTL. There's no way to force an immediate cache purge short of using the Cloudflare API.

- **GitHub Trees API scalability:** file-server's fuzzy matching fetches the entire repo tree via `GET /git/trees/{branch}?recursive=1`. Currently fast because the repo is small. If the repo grows to thousands of files, this could become slow and hit API payload limits. Consider caching the tree result or narrowing the search scope if this becomes an issue.

- **No overlapping rule detection in match:** Rules are evaluated first-match-wins. If two rules could match the same input (e.g., one rule matches `control + x86` and another matches `control + amd`, and someone requests `control-x86-amd`), the first one silently wins. No warning or logging for ambiguous matches.

- **match service `github_release` always fetches latest:** There's no way to pin a specific release version. If you need to serve a specific (non-latest) release, use the `url` field with a direct download link instead.
