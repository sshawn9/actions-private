# match

Keyword-matching download router running on Cloudflare Workers. Routes requests to `match.sshawn9.com/<keywords>` by matching keywords in the URL path against a rule set, then proxies the corresponding file. Supports auto-resolving the latest GitHub release asset from private repositories.

## Usage

```bash
# Download latest motion_control deb for ARM
curl -fsSL -OJ https://match.sshawn9.com/control-aarch64

# Keywords can appear in any order
curl -fsSL -OJ https://match.sshawn9.com/aarch64-control

# Download latest motion_control deb for x86
curl -fsSL -OJ https://match.sshawn9.com/control-x86

# List all available rules
curl https://match.sshawn9.com/
```

No authentication required — all endpoints are publicly accessible.

## Keyword Matching

Keywords are defined as a **two-dimensional array** with AND/OR semantics:

- **Outer array**: AND — every group must match
- **Inner array**: OR — at least one keyword in the group must match

Matching is **case-insensitive** and checks if the URL path **contains** the keyword as a substring.

**Example:**

```json
"keywords": [["control"], ["x86", "amd", "amd64"]]
```

This matches any path that contains `control` **AND** (`x86` **OR** `amd` **OR** `amd64`):

| Path | Match | Reason |
|------|:-----:|--------|
| `/control-x86` | Yes | contains "control" + "x86" |
| `/x86-control` | Yes | order doesn't matter |
| `/control-amd64` | Yes | contains "control" + "amd64" |
| `/control` | No | missing x86/amd/amd64 |
| `/x86` | No | missing "control" |
| `/control-arm` | No | "arm" is not in the OR group |

Rules are evaluated in array order; the **first matching rule wins**.

## Rules Format

Rules are defined in `worker/src/rules.json` and bundled into the Worker at build time. Changes to `rules.json` require a push to `main` (CI/CD auto-redeploys since the workflow watches `match/**`).

Each rule has two supported download source types:

### 1. `github_release` — Auto-resolve latest release asset

```json
{
  "name": "motion-control-arm-deb",
  "keywords": [["control"], ["arm", "aarch64"]],
  "github_release": {
    "repo": "autonomous-group/motion_control",
    "asset_keywords": [["aarch64", "arm64"], [".deb"]]
  }
}
```

| Field | Description |
|-------|-------------|
| `name` | Human-readable identifier (shown in rule listing at `/`) |
| `keywords` | 2D array for matching the URL path (AND/OR semantics) |
| `github_release.repo` | GitHub `owner/repo` to fetch latest release from |
| `github_release.asset_keywords` | 2D array (same AND/OR semantics) for matching asset filenames within the release |

**Resolution flow:**
1. Calls `GET /repos/{owner}/{repo}/releases/latest` via GitHub API
2. Iterates through release assets, applying `asset_keywords` matching against each asset filename
3. Downloads the first matching asset via the API asset endpoint (`Accept: application/octet-stream`)
4. This approach works for both **public and private** repositories (uses `GITHUB_TOKEN` for authentication)

### 2. `url` — Static download URL

```json
{
  "name": "some-static-file",
  "keywords": [["something"]],
  "url": "https://example.com/file.zip"
}
```

| Field | Description |
|-------|-------------|
| `url` | Direct download URL (fetched as-is) |

Both types can be mixed in the same `rules.json`.

## GitHub Release Resolution

When a rule uses `github_release`, the Worker:

1. Fetches `https://api.github.com/repos/{repo}/releases/latest` with `GITHUB_TOKEN` for auth
2. Scans the release's `assets` array for the first asset whose filename matches `asset_keywords`
3. Downloads via `https://api.github.com/repos/{repo}/releases/assets/{asset_id}` with `Accept: application/octet-stream`

**Why not `browser_download_url`?** For private repositories, `browser_download_url` returns 404 even with an auth token. The API asset endpoint returns a signed redirect URL that works for both public and private repos.

**GitHub API rate limit:** Authenticated requests allow 5,000/hour. Each uncached request uses 2 API calls (1 for latest release, 1 for asset download). With 1-hour edge caching, actual API usage is minimal.

## Current Rules

| Name | Keywords | Repo | Asset Match |
|------|----------|------|-------------|
| motion-control-x86-deb | control + (x86\|amd) | autonomous-group/motion_control | (x86\|x86_64\|amd64) + .deb |
| motion-control-arm-deb | control + (arm\|aarch64) | autonomous-group/motion_control | (aarch64\|arm64) + .deb |
| communication-utilities-x86-deb | communication + (x86\|amd) | autonomous-group/communication_utilities | (x86\|x86_64\|amd64) + .deb |
| communication-utilities-arm-deb | communication + (arm\|aarch64) | autonomous-group/communication_utilities | (aarch64\|arm64) + .deb |
| msg-converter-x86-deb | converter + (x86\|amd) | autonomous-group/msg_converter | (x86\|x86_64\|amd64) + .deb |
| msg-converter-arm-deb | converter + (arm\|aarch64) | autonomous-group/msg_converter | (aarch64\|arm64) + .deb |
| local-roadnet-x86-deb | roadnet + (x86\|amd) | autonomous-group/local_roadnet | (x86\|x86_64\|amd64) + .deb |
| local-roadnet-arm-deb | roadnet + (arm\|aarch64) | autonomous-group/local_roadnet | (aarch64\|arm64) + .deb |
| autonomous-joystick-x86-deb | joystick + (x86\|amd) | autonomous-group/autonomous_joystick | (x86\|x86_64\|amd64) + .deb |
| autonomous-joystick-arm-deb | joystick + (arm\|aarch64) | autonomous-group/autonomous_joystick | (aarch64\|arm64) + .deb |
| protopico-x86-deb | protopico + (x86\|amd) | autonomous-group/protopico | (x86\|x86_64\|amd64) + .deb |
| protopico-arm-deb | protopico + (arm\|aarch64) | autonomous-group/protopico | (aarch64\|arm64) + .deb |
| fake-pub-x86-deb | fake + (x86\|amd) | autonomous-group/fake_pub | (x86\|x86_64\|amd64) + .deb |
| fake-pub-arm-deb | fake + (arm\|aarch64) | autonomous-group/fake_pub | (aarch64\|arm64) + .deb |

## Caching

- **Edge cache TTL**: 1 hour (`s-maxage=3600`)
- **Cache key**: `{origin}/{path}` (the full URL path as requested)
- After a new release is published on GitHub, the cached version expires within 1 hour, after which the new version is served automatically

## Adding a New Rule

1. Edit `match/worker/src/rules.json`
2. Add a new rule object:

```json
{
  "name": "my-package-arm-deb",
  "keywords": [["mypackage"], ["arm", "aarch64"]],
  "github_release": {
    "repo": "org/my-package",
    "asset_keywords": [["aarch64", "arm64"], [".deb"]]
  }
}
```

3. Push to `main` — CI/CD auto-deploys the updated Worker

**Tips:**
- Place more specific rules before less specific ones (first match wins)
- `asset_keywords` uses the same AND/OR matching as `keywords` — use separate inner arrays for AND, group alternatives in the same inner array for OR
- Include file extensions like `".deb"` in `asset_keywords` to distinguish between different package formats
