# cf-dns

Manage Cloudflare DNS records, Origin Rules, and SSL/TLS mode with Terraform.

All config lives in `terraform.tfvars`. Edit, push to main, GitHub Actions applies automatically.

## Files

```
cf-dns/
├── main.tf            # Terraform & Cloudflare provider version
├── variables.tf       # Variable definitions (no need to edit)
├── dns.tf             # DNS record logic (no need to edit)
├── rules.tf           # Origin Rules logic (no need to edit)
├── zone.tf            # Zone settings: SSL/TLS mode (no need to edit)
├── terraform.tfvars   # ★ All config goes here
├── terraform.tfstate  # State file (auto-managed, do not edit)
└── .gitignore
```

## Initial Setup

### 1. Get Zone ID

Cloudflare dashboard → select domain → right sidebar "API" section → copy **Zone ID**.

### 2. Create API Token

Cloudflare dashboard → My Profile → API Tokens → Create Token:

- **Zone - DNS - Edit**
- **Zone - Zone Rulesets - Edit**
- **Zone - Zone Settings - Edit**
- Zone Resources → Include → select your domain

### 3. Add GitHub Secret

Repo Settings → Secrets and variables → Actions → New repository secret:

- Name: `CF_API_TOKEN`
- Value: the token from step 2

## Usage

Edit `terraform.tfvars`, then push (or manually trigger the workflow).

### Add a server

```hcl
servers = {
  rn-2c = "104.129.51.144"
  us1   = "5.6.7.8"          # new
}
```

### Add a DNS record

Key = subdomain. The record points to the IP of the named server.

```hcl
dns_records = {
  easytier  = { server = "rn-2c" }
  et-config = { server = "rn-2c" }
  blog      = { server = "us1" }                      # blog.sshawn9.com -> us1
  api       = { server = "us1", proxied = false }      # direct, no CF proxy
}
```

Parameters:

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `server` | yes | - | Name from `servers` map |
| `type` | no | `"A"` | DNS record type |
| `proxied` | no | `true` | Route through Cloudflare proxy (orange cloud) |

### Add an Origin Rule (port override)

Required when a proxied service listens on a non-standard port (not 80/443):

```hcl
origin_rules = {
  "EasyTier Web panel"     = { hostname = "easytier.sshawn9.com",  port = 11211 }
  "EasyTier Config server" = { hostname = "et-config.sshawn9.com", port = 22020 }
  "Grafana"                = { hostname = "grafana.sshawn9.com",   port = 3000  }
}
```

> Not needed for `proxied = false` records — clients connect to `IP:port` directly.

### Migrate services to another server

Change the `server` value:

```hcl
dns_records = {
  easytier  = { server = "us1" }   # was rn-2c
  et-config = { server = "us1" }   # was rn-2c
}
```

### Change a server IP

Update one value in `servers` — all DNS records pointing to it update automatically:

```hcl
servers = {
  rn-2c = "9.8.7.6"   # new IP, all rn-2c records follow
}
```

### Delete a record

Remove the line from `dns_records` or `origin_rules`. Terraform deletes it from Cloudflare on next apply.

### Change SSL/TLS mode

```hcl
ssl_mode = "flexible"   # off | flexible | full | strict
```

This is a zone-wide setting (applies to all subdomains).

## Full Example

```hcl
zone_id  = "abc123def456"
ssl_mode = "flexible"

servers = {
  hk1 = "103.1.2.3"
  us1 = "198.51.100.1"
  jp1 = "203.0.113.5"
}

dns_records = {
  easytier  = { server = "hk1" }
  et-config = { server = "hk1" }
  blog      = { server = "us1" }
  api       = { server = "us1" }
  grafana   = { server = "jp1" }
  ssh-jp    = { server = "jp1", proxied = false }
}

origin_rules = {
  "EasyTier Web"    = { hostname = "easytier.sshawn9.com",  port = 11211 }
  "EasyTier Config" = { hostname = "et-config.sshawn9.com", port = 22020 }
  "Grafana"         = { hostname = "grafana.sshawn9.com",   port = 3000  }
}
```

## Importing Existing Records

If a DNS record already exists in Cloudflare, `terraform apply` will fail with a conflict. Import it first:

1. Find the record ID in the Cloudflare dashboard or via API
2. Add an import block to `main.tf`:

```hcl
import {
  to = cloudflare_record.dns["easytier"]
  id = "<zone_id>/<record_id>"
}
```

3. Run apply once, then remove the import block

Alternatively, delete the existing record from the dashboard and let Terraform recreate it.

## Notes

- **Origin Rules are managed as a whole ruleset.** If you have manually created Origin Rules in the dashboard, add them to `terraform.tfvars` or they will be overwritten. DNS records do not have this problem — Terraform only touches records it manages.
- **Do not edit `terraform.tfstate` manually.** It is committed by GitHub Actions after each apply.
- **API Token permissions:** Zone DNS Edit + Zone Rulesets Edit + Zone Settings Edit.
