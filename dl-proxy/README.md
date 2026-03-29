# dl-proxy

Cloudflare Worker proxy for downloading resources from GitHub and other domains that may be inaccessible in certain regions.

## Usage

```
https://dl.sshawn9.com/<domain>/<path>?token=<your-token>
```

### Download a file

```bash
# Download EasyTier deb package
curl -fsSL -o easytier-gui.deb \
  "https://dl.sshawn9.com/github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-gui_2.4.5_amd64.deb?token=tmp339"

# Auto-detect filename with -O
curl -fsSL -O \
  "https://dl.sshawn9.com/github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-linux-x86_64-v2.4.5.zip?token=tmp339"

# Download raw file from GitHub repo
curl -fsSL \
  "https://dl.sshawn9.com/raw.githubusercontent.com/EasyTier/EasyTier/main/README.md?token=tmp339"
```

### Query parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `token`   | Yes      | Auth token to prevent unauthorized access |
| `nocache` | No       | Skip edge cache and fetch from origin |

```bash
# Force fresh download (skip cache)
curl -fsSL -o file.deb "https://dl.sshawn9.com/github.com/...?token=tmp339&nocache"
```

## Configuration

Edit `worker/src/config.ts`:

- **DL_TOKEN** — Auth token
- **ALLOWED_DOMAINS** — Only domains in this list can be proxied

Current whitelist:
- `github.com`
- `raw.githubusercontent.com`
- `objects.githubusercontent.com`
- `github-releases.githubusercontent.com`

## Deployment

Push changes under `dl-proxy/worker/` to main branch triggers GitHub Actions automatically. Can also be triggered manually from the Actions page.

Manual deploy:

```bash
cd dl-proxy/worker
npm install
npx wrangler deploy
```

## Notes

- Token is visible in the URL — do not share full download links publicly
- Responses are cached on Cloudflare edge for 1 hour by default; use `?nocache` to bypass
- Change token by editing `DL_TOKEN` in `config.ts` and redeploying
