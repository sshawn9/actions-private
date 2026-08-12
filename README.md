# actions-private

Infrastructure-as-code repository for the **sshawn9.com** domain ecosystem, powered by Cloudflare Workers and Terraform.

## Architecture

```
                        Clients (curl, browsers, scripts)
                                     |
                 ┌───────────────────┼───────────────────┐
                 |                   |                   |
        file.sshawn9.com    match.sshawn9.com     dl.sshawn9.com
                 |                   |                   |
          ┌──────────────┐  ┌────────────────┐  ┌────────────────┐
          |  file-server |  |     match      |  |    dl-proxy    |
          |    Worker    |  |    Worker      |  |    Worker      |
          └──────┬───────┘  └───────┬────────┘  └────────┬───────┘
                 |                  |                    |
          GitHub Repo         GitHub Releases      Whitelisted
        (files + config        (latest asset)     External Domains
          injection)                                (with auth)

  DNS, redirects, zone settings, and stable custom domains managed by Terraform (cf-dns/)
```

## Services

| Service | Domain | Purpose | Directory |
|---------|--------|---------|-----------|
| **website** | `sshawn9.com` | Stable custom domain for the production `sshawn9-com` Worker; preview versions remain isolated on `sshawn9-com-preview` | `cf-dns/` |
| **file-server** | `file.sshawn9.com/<name>` | Path-based file server with config injection and fuzzy matching | `file-server/` |
| **match** | `match.sshawn9.com/<keywords>` | Keyword-matching download router, auto-resolves latest GitHub release assets | `match/` |
| **dl-proxy** | `dl.sshawn9.com/<domain>/<path>?token=xxx` | Authenticated download proxy for whitelisted domains | `dl-proxy/` |
| **cf-dns** | N/A | Terraform-managed DNS, redirects, Worker custom domains, and zone settings | `cf-dns/` |

## Tech Stack

- **Runtime**: Cloudflare Workers (TypeScript)
- **Build & Deploy**: Wrangler v4
- **DNS & Infrastructure**: Terraform with Cloudflare Provider v5.23.0 and R2 remote state
- **CI/CD**: GitHub Actions (auto-deploy on push to `main`)
- **Node.js**: v24

## Directory Structure

```
actions-private/
├── file-server/          # Path-based file server
│   ├── files/            #   Served files (scripts, configs, etc.)
│   ├── routes.json       #   Name-to-file mapping
│   └── worker/           #   Cloudflare Worker source
├── match/                # Keyword-matching download router
│   └── worker/
│       └── src/
│           ├── index.ts  #   Worker logic
│           └── rules.json#   Matching rules (bundled into Worker)
├── dl-proxy/             # Authenticated download proxy
│   └── worker/
│       └── src/
│           ├── index.ts  #   Worker logic
│           └── config.ts #   Tokens & domain whitelist
├── cf-dns/               # Terraform DNS management
│   ├── terraform.tfvars  #   Cloudflare zone ID
│   ├── backend.tf        #   R2 remote-state backend
│   ├── site-worker.tf    #   Production website custom domain
│   └── *.tf              #   Explicit Terraform resources
├── shared/               # Shared configuration files
│   └── *.conf            #   KEY=VALUE files for template injection
└── .github/workflows/    # CI/CD pipelines
    ├── file-server.yml
    ├── match.yml
    ├── dl-proxy.yml
    └── cf-dns.yml
```

## Deployment

All services auto-deploy when changes are pushed to the `main` branch:

| Service | Trigger Path | Deploy Method |
|---------|-------------|---------------|
| file-server | `file-server/worker/**` | `npx wrangler deploy` |
| match | `match/**` | `npx wrangler deploy` |
| dl-proxy | `dl-proxy/worker/**` | `npx wrangler deploy` |
| cf-dns | `cf-dns/**` | Pull request plan; serialized apply on `main` using R2 remote state |

All workflows also support manual trigger via `workflow_dispatch`.

## Required Secrets

Configure these in GitHub repository settings under **Settings > Secrets and variables > Actions**:

| Secret | Used By | Purpose |
|--------|---------|---------|
| `CLOUDFLARE_API_TOKEN` | All services | Account-owned `cfat_` token for Workers, Terraform, and R2 state |
| `GH_PAT` | file-server, match, dl-proxy | GitHub Personal Access Token, injected as `GITHUB_TOKEN` Worker secret for private repo access |

The `cf-dns` workflow derives the Cloudflare account ID and R2 S3 credentials
from the account-owned token. Its state bucket name,
`sshawn9-terraform-state`, is fixed in `cf-dns/backend.tf`.

## Shared Configuration

The `shared/` directory contains `.conf` files with `KEY=VALUE` entries. These are used by the **file-server** Worker to perform template injection: any `{{KEY}}` placeholder in served files is replaced with the corresponding value at runtime.

Current config files:
- `shared/dl-proxy.conf` — Contains `DL_PROXY` and `DL_TOKEN` values used by installation scripts

## Adding a New Service

1. Create a directory: `<service>/worker/` with `src/index.ts`, `wrangler.toml`, `package.json`, `tsconfig.json`
2. Add stable custom domains to `cf-dns/`; keep Worker code and version deployment in the service repository
3. Add a GitHub Actions workflow at `.github/workflows/<service>.yml` (copy an existing one as template)
4. Push to `main` — the workflow deploys automatically
5. Set Worker secrets if needed: the workflow should include a step to inject `GITHUB_TOKEN`
