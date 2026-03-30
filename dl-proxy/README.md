# dl-proxy

Authenticated download proxy running on Cloudflare Workers. Proxies file downloads from whitelisted domains (primarily GitHub) via `dl.sshawn9.com`, providing access to resources that may be inaccessible in certain regions.

## Usage

```bash
# Basic download
curl -fsSL -o easytier-gui.deb \
  "https://dl.sshawn9.com/github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-gui_2.4.5_amd64.deb?token=xxx"

# Auto-detect filename with -O (uses Content-Disposition header)
curl -fsSL -OJ \
  "https://dl.sshawn9.com/github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-linux-x86_64-v2.4.5.zip?token=xxx"

# Download raw file from GitHub repo
curl -fsSL \
  "https://dl.sshawn9.com/raw.githubusercontent.com/EasyTier/EasyTier/main/README.md?token=xxx"

# Bypass cache for fresh download
curl -fsSL -o file.deb \
  "https://dl.sshawn9.com/github.com/...?token=xxx&nocache"

# Show usage info (no token needed)
curl https://dl.sshawn9.com/
```

**URL format**: `https://dl.sshawn9.com/<domain>/<path>?token=<your-token>`

The `<domain>/<path>` portion is converted to `https://<domain>/<path>` and fetched by the Worker.

### Query Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `token` | Yes | Authentication token (see Managing Tokens below) |
| `nocache` | No | Skip edge cache and fetch directly from origin (presence is enough, no value needed) |

## Authentication

Every request must include a valid `token` query parameter. Requests without a token or with an invalid token receive `403 Unauthorized`.

Tokens are defined in `worker/src/config.ts` as the `DL_TOKENS` array. Multiple tokens are supported, allowing different tokens for different users or purposes (e.g., private vs shared tokens).

**Security note:** Tokens are visible in the URL. Do not share full download links publicly.

## Domain Whitelist

Only requests targeting whitelisted domains are proxied. Others receive `403 Domain not allowed`.

The whitelist is defined in `worker/src/config.ts`:

| Domain | Receives GitHub PAT | Description |
|--------|:-------------------:|-------------|
| `github.com` | Yes | GitHub release downloads, repo pages |
| `raw.githubusercontent.com` | Yes | Raw file content from repos |
| `api.github.com` | Yes | GitHub API endpoints |
| `objects.githubusercontent.com` | No | GitHub LFS and release asset storage |
| `github-releases.githubusercontent.com` | No | GitHub release asset CDN |

Domains marked with "Receives GitHub PAT" automatically get an `Authorization: token <GITHUB_TOKEN>` header injected, enabling access to private repositories.

Subdomain matching is supported: if `github.com` is whitelisted, `api.github.com` also passes (via `endsWith` check).

## Caching

- **Edge cache TTL**: 1 hour (`s-maxage=3600`)
- **Cache key**: The target URL (e.g., `https://github.com/...`)
- **Bypass**: Add `?nocache` to skip the cache and fetch from origin
- Same target URL from different users/tokens shares the same cache entry

## Error Codes

| Status | Condition | Response Body |
|--------|-----------|---------------|
| 200 | No path provided (root request) | Usage instructions |
| 403 | Missing or invalid token | `Unauthorized.` |
| 403 | Target domain not in whitelist | `Domain not allowed: {hostname}` |
| 400 | Path cannot be parsed as a valid URL | `Invalid URL path.` |
| 404 | Upstream returned 404 | `Download failed: 404 Not Found` |
| 502 | Upstream returned other error | `Download failed: {status} {statusText}` |

## Managing Tokens

Edit `worker/src/config.ts`:

```typescript
export const DL_TOKENS: string[] = [
  "shawn326",     // Private
  "bit472",       // Shared
  "c3i",          // Shared
];
```

- Add a new token: append to the array
- Revoke a token: remove from the array
- Push to `main` to redeploy with updated tokens

## Managing Domains

Edit the `ALLOWED_DOMAINS` array in `worker/src/config.ts`:

```typescript
export const ALLOWED_DOMAINS: string[] = [
  ...GITHUB_DOMAINS,
  "objects.githubusercontent.com",
  "github-releases.githubusercontent.com",
  // Add new domains here
];
```

If the new domain should receive the GitHub PAT header, also add it to `GITHUB_DOMAINS`.

Push to `main` to redeploy.
