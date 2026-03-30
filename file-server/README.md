# file-server

Path-based file server running on Cloudflare Workers. Serves files from this repository via `file.sshawn9.com/<name>` with automatic config value injection and fuzzy filename matching.

## Usage

```bash
# Exact match (name defined in routes.json)
curl -fsSL https://file.sshawn9.com/iet | bash

# Fuzzy match (searches files/ for a filename containing the input)
curl -fsSL https://file.sshawn9.com/install-easytier | bash

# Show usage info
curl https://file.sshawn9.com/
```

## Routing Logic

The Worker resolves a `<name>` to a file using a two-layer fallback:

1. **Exact match** — Looks up `<name>` in `routes.json`. If found, serves the mapped file directly.
2. **Fuzzy match** — If no exact match, fetches the full directory tree of `file-server/files/` via the GitHub Trees API, and returns the first file whose filename **contains** `<name>` (case-insensitive).
3. **404** — If neither match finds a file, returns `Not found: <name>`.

## Configuration

### routes.json

Maps short names to file paths (relative to `file-server/files/`):

```json
{
  "iet": "scripts/install-easytier.sh",
  "deploy-easytier-web": "scripts/deploy-easytier-web.sh"
}
```

- Keys are the URL path segments users will request
- Values are relative paths within `file-server/files/`
- This file is loaded dynamically from GitHub at runtime (changes take effect after cache expires, no redeployment needed)

### Config Injection

Before serving a file, the Worker loads all `.conf` files from the `shared/` directory and replaces `{{KEY}}` placeholders in the file content with their corresponding values.

**How it works:**

1. Worker lists all files in `shared/` via GitHub API
2. Reads each `.conf` file (format: one `KEY=VALUE` per line)
3. For every entry, replaces all occurrences of `{{KEY}}` in the served file with `VALUE`

**Example:**

`shared/dl-proxy.conf`:
```
DL_PROXY=https://dl.sshawn9.com
DL_TOKEN=shawn326
```

A served script containing `{{DL_PROXY}}` will have it replaced with `https://dl.sshawn9.com` at serve time.

## Fuzzy Matching

When no exact route is found, the Worker uses the GitHub Trees API (`GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1`) to fetch all file paths under `file-server/files/`. It then iterates through the tree and returns the first file whose **filename** (not full path) contains the requested `<name>` (case-insensitive).

For example, requesting `/install-easytier` would match `scripts/install-easytier.sh` because the filename `install-easytier.sh` contains `install-easytier`.

## Caching

- **Edge cache TTL**: 5 minutes (`s-maxage=300`)
- **Cache key**: `{origin}/{name}` (full path-based, so different names have independent caches)
- After pushing file or config changes, cached responses expire within 5 minutes

## Adding a New File

1. Place your file in `file-server/files/` (any subdirectory structure is fine)
2. **(Optional)** Add an entry to `routes.json` if you want a short alias (e.g., `"myalias": "path/to/file.sh"`)
3. If you skip step 2, the file is still accessible via fuzzy matching (e.g., the filename itself)
4. Use `{{KEY}}` placeholders in your file if you need config value injection
5. Push to `main` — the file is available immediately (no Worker redeployment needed, subject to cache TTL)

**Note:** Only changes to `file-server/worker/**` trigger a Worker redeployment. Changes to `files/`, `routes.json`, or `shared/*.conf` take effect on the next uncached request since these are fetched from GitHub at runtime.

## File Inventory

| Route | File Path | Description |
|-------|-----------|-------------|
| `/iet` | `scripts/install-easytier.sh` | EasyTier VPN client installer — downloads binary, sets up systemd service, configures machine ID |
| `/deploy-easytier-web` | `scripts/deploy-easytier-web.sh` | EasyTier web dashboard deployment — installs binary, GeoIP DB, systemd service, Cloudflare origin rules, firewall |
