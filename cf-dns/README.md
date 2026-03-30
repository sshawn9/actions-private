# cf-dns

Terraform-managed Cloudflare DNS records, Origin Rules, and SSL/TLS settings for the `sshawn9.com` zone. All config lives in `terraform.tfvars` — edit, push to `main`, and GitHub Actions runs `terraform apply` automatically.

## Usage

All configuration changes are made by editing `terraform.tfvars` and pushing to the `main` branch. The CI pipeline handles `terraform init` and `terraform apply`.

For manual operations (rarely needed):

```bash
cd cf-dns
export CLOUDFLARE_API_TOKEN="your-token"
terraform init
terraform plan    # Preview changes
terraform apply   # Apply changes
```

## Current Configuration

### DNS Records

| Subdomain | Type | Server | IP Address | Proxied | Purpose |
|-----------|------|--------|------------|:-------:|---------|
| `easytier` | A | rn-2c | 104.129.51.144 | Yes | EasyTier web panel |
| `et-config` | A | rn-2c | 104.129.51.144 | Yes | EasyTier config server |

**Note:** Worker custom domains (`file.sshawn9.com`, `match.sshawn9.com`, `dl.sshawn9.com`) are **not** managed here — Cloudflare Workers automatically create and manage DNS records for `custom_domain` routes defined in `wrangler.toml`.

### Origin Rules

| Description | Hostname | Destination Port |
|-------------|----------|:----------------:|
| EasyTier Web panel | `easytier.sshawn9.com` | 11212 |
| EasyTier Config server | `et-config.sshawn9.com` | 22020 |

Origin Rules override the destination port for proxied requests. Without these rules, Cloudflare forwards traffic to port 80/443 on the origin. Not needed for `proxied = false` records — clients connect to `IP:port` directly.

### Servers

| Alias | IP Address |
|-------|------------|
| rn-2c | 104.129.51.144 |

Server aliases allow DNS records to reference servers by name. Changing an IP in `servers` automatically updates all records pointing to that alias.

### SSL/TLS Mode

Current mode: **flexible**

| Mode | Description |
|------|-------------|
| `off` | No encryption |
| `flexible` | Encrypted client-to-Cloudflare, **plaintext** Cloudflare-to-origin (no cert needed on origin) |
| `full` | Encrypted end-to-end (origin needs a cert, self-signed OK) |
| `strict` | Encrypted end-to-end (origin needs a valid/trusted cert) |

This is a zone-wide setting (applies to all subdomains).

## Configuration Files

### terraform.tfvars

This is the **only file you need to edit** for configuration changes:

```hcl
zone_id  = "2cbfbc36ae05bc041b712442e2f7b584"
ssl_mode = "flexible"

servers = {
  rn-2c = "104.129.51.144"
}

dns_records = {
  easytier  = { server = "rn-2c" }
  et-config = { server = "rn-2c" }
}

origin_rules = {
  "EasyTier Web panel"     = { hostname = "easytier.sshawn9.com",  port = 11212 }
  "EasyTier Config server" = { hostname = "et-config.sshawn9.com", port = 22020 }
}
```

### Terraform Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration (Cloudflare provider v4.x, reads `CLOUDFLARE_API_TOKEN` from env) |
| `variables.tf` | Variable definitions with types, defaults, and descriptions |
| `dns.tf` | `cloudflare_record` resource — creates DNS records from `dns_records` map |
| `rules.tf` | `cloudflare_ruleset` resource — creates Origin Rules from `origin_rules` map |
| `zone.tf` | `cloudflare_zone_settings_override` resource — sets SSL/TLS mode |
| `terraform.tfstate` | Terraform state file (auto-managed by CI, do not edit manually) |

## Adding a DNS Record

1. If the server IP is new, add it to `servers`:
   ```hcl
   servers = {
     rn-2c    = "104.129.51.144"
     new-srv  = "203.0.113.50"
   }
   ```

2. Add the DNS record to `dns_records`:
   ```hcl
   dns_records = {
     easytier  = { server = "rn-2c" }
     myapp     = { server = "new-srv" }
     myapi     = { server = "new-srv", type = "A", proxied = false }
   }
   ```

   | Parameter | Required | Default | Description |
   |-----------|----------|---------|-------------|
   | `server` | Yes | — | Name from `servers` map |
   | `type` | No | `"A"` | DNS record type |
   | `proxied` | No | `true` | Route through Cloudflare proxy (orange cloud) |

3. If the origin uses a non-standard port (not 80/443), add an Origin Rule:
   ```hcl
   origin_rules = {
     "My App" = { hostname = "myapp.sshawn9.com", port = 8080 }
   }
   ```

4. Push to `main` — CI runs `terraform apply` automatically

### Other Common Operations

**Migrate services to another server** — change the `server` value:
```hcl
easytier = { server = "us1" }   # was rn-2c
```

**Change a server IP** — update one value in `servers`, all referencing records follow:
```hcl
servers = {
  rn-2c = "9.8.7.6"   # new IP
}
```

**Delete a record** — remove the line from `dns_records` or `origin_rules`. Terraform deletes it from Cloudflare on next apply.

## SSL/TLS Mode

To change the SSL/TLS mode:
```hcl
ssl_mode = "full"
```

**Important:** Switching to `full` or `strict` requires a valid SSL certificate on the origin server.

## State Management

Terraform state (`terraform.tfstate`) is committed directly to this git repository. After each `terraform apply`, the CI pipeline automatically commits the updated state file with the message `"Update Terraform state"`.

- State is versioned alongside configuration
- No external state backend required
- Pull before making local changes to avoid state conflicts
- The CI job has `contents: write` permission to push state updates

## Notes

- **Origin Rules are managed as a whole ruleset.** If you have manually created Origin Rules in the Cloudflare dashboard, add them to `terraform.tfvars` or they will be overwritten. DNS records do not have this problem — Terraform only touches records it manages.
- **Importing existing records:** If a DNS record already exists in Cloudflare, `terraform apply` will fail with a conflict. Either delete the existing record from the dashboard first, or use a Terraform import block:
  ```hcl
  import {
    to = cloudflare_record.dns["easytier"]
    id = "<zone_id>/<record_id>"
  }
  ```
  Run apply once, then remove the import block.
- **API Token permissions required:** Zone DNS Edit + Zone Rulesets Edit + Zone Settings Edit.
