# cf-dns

Terraform-managed Cloudflare configuration for the `sshawn9.com` zone.

The configuration uses explicit Cloudflare provider resources rather than a
custom `terraform.tfvars` abstraction. This keeps rule ordering visible and
makes Terraform state addresses correspond directly to Cloudflare resources.

## Managed resources

### DNS records

| Hostname | Type | Content | Proxied | Purpose |
|---|---|---|:---:|---|
| `easytier.sshawn9.com` | A | `104.129.51.144` | Yes | EasyTier web panel |
| `et-config.sshawn9.com` | A | `104.129.51.144` | Yes | EasyTier config server |
| `www.sshawn9.com` | A | `192.0.2.1` | Yes | Originless hostname for the canonical redirect |

`192.0.2.1` is a reserved documentation address recommended by Cloudflare for
originless hostnames. Because the record is proxied, the Single Redirect rule
runs at Cloudflare's edge and no connection is made to that address.

The website custom domain `sshawn9.com` is managed by Terraform. Service-owned
custom domains such as `file.sshawn9.com`, `match.sshawn9.com`, and
`dl.sshawn9.com` remain in their respective Worker deployment configurations.

### Website preview access

The production custom domain `sshawn9.com` remains public. Cloudflare Access
protects every non-production website endpoint:

- Version previews of the production `sshawn9-com` Worker.
- The stable `sshawn9-com-preview` workers.dev endpoint.
- Branch aliases and immutable versions of `sshawn9-com-preview`.

The Access policy allows accepted members of this Cloudflare account, uses a
24-hour session, and does not expose the application in the Access launcher.
The destination patterns include the Worker name, so they do not affect other
Workers in the same account.

### Single Redirects

`www.sshawn9.com` permanently redirects to `https://sshawn9.com` with:

- HTTP status `308`, preserving the original HTTP method.
- The original request path.
- The original query string.

For example, `http://www.sshawn9.com/a?x=1` becomes
`https://sshawn9.com/a?x=1`.

All zone-level Single Redirect rules must be kept in the ordered `rules` list
of `cloudflare_ruleset.single_redirects`. Cloudflare permits only one zone
entry-point ruleset for this phase, and the first matching redirect wins.

### Origin Rules

| Hostname | Destination port |
|---|---:|
| `easytier.sshawn9.com` | 11212 |
| `et-config.sshawn9.com` | 22020 |

### Zone settings

The zone-wide SSL/TLS mode is `flexible`. Changing it to `full` or `strict`
requires compatible TLS certificates on every affected origin.

## File layout

| File | Purpose |
|---|---|
| `backend.tf` | Cloudflare R2 remote-state backend |
| `main.tf` | Terraform and Cloudflare provider versions |
| `variables.tf` | Deployment inputs |
| `terraform.tfvars` | The zone ID only |
| `dns.tf` | Explicit DNS record resources |
| `rules.tf` | Ordered Origin Rules and Single Redirects rulesets |
| `site-access.tf` | Access application and reusable policy for website previews |
| `site-worker.tf` | Production website custom domain |
| `zone.tf` | Individual zone settings |
| `migrations.tf` | State-preserving provider v4 to v5 migration declarations |

## Versions

- Terraform: `>= 1.8, < 2.0` (`1.15.8` in GitHub Actions)
- Cloudflare provider: `5.23.0`

The committed `.terraform.lock.hcl` pins the provider package and checksums.
Provider upgrades should be made intentionally in a separate change.

## Authentication and permissions

The Cloudflare provider and R2 backend share one account-owned `cfat_` token
from `CLOUDFLARE_API_TOKEN`. It needs:

- Zone DNS Edit
- Zone Settings Edit
- Zone Origin Rules Edit
- Zone Single Redirect Edit
- Account Workers Scripts Edit (called `Workers Scripts Write` by the API)
- Access: Apps and Policies Edit (called `Access: Apps and Policies Write` by
  the API)
- R2 Object Read and Write, scoped to the Terraform state bucket when possible

The workflow discovers the account through the Accounts API and retrieves the
account token ID from the Account Token Verify API. For the R2 S3 backend it
uses the token ID as the access key ID and the SHA-256 digest of the token value
as the secret access key. Neither the account ID nor separate R2 credentials
need to be configured. The token must expose exactly one Cloudflare account.

## GitHub configuration

Configure this Actions secret:

| Secret | Purpose |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Account-owned `cfat_` token for zone resources and R2 state |

Pull requests run formatting, validation, and plan. Pushes to `main` run the
same checks and apply the saved plan. Workflow concurrency serializes all
operations for this state.

## One-time remote-state migration

The R2 bucket must exist and the `cfat_` token must have access to it before
enabling the new workflow. Its fixed name is `sshawn9-terraform-state`, as
declared in `backend.tf`. For local migration, derive the backend credentials
from the same token:

```bash
export CLOUDFLARE_API_TOKEN="<cfat_ account token>"

ACCOUNT_ID="$(curl --fail-with-body --silent --show-error \
  "https://api.cloudflare.com/client/v4/accounts" \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
  jq -er 'if .success == true and (.result | length) == 1 then .result[0].id else error("expected one account") end')"

export AWS_ACCESS_KEY_ID="$(curl --fail-with-body --silent --show-error \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tokens/verify" \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
  jq -er 'if .success == true and .result.status == "active" then .result.id else error("token is not active") end')"
export AWS_SECRET_ACCESS_KEY="$(printf '%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -d' ' -f1)"
export AWS_ENDPOINT_URL_S3="https://$ACCOUNT_ID.r2.cloudflarestorage.com"
```

Either run the `Terraform Cloudflare DNS` workflow manually with
`migrate_state=true`, or copy the currently committed local state into R2 from
this directory:

```bash
terraform init -migrate-state -force-copy

terraform state list
```

Verify that the remote state contains the existing DNS records and Origin
Rules before deleting the tracked `terraform.tfstate` file. Its final removal
must only be committed after the R2 copy has been verified. Normal CI runs are
intentionally blocked while the bootstrap state remains tracked.

The provider v5 migration deliberately removes the legacy aggregate
`cloudflare_zone_settings_override.ssl` address from local state. On the first
authenticated plan/apply, `migrations.tf` imports the existing `ssl` setting as
`cloudflare_zone_setting.ssl`; it does not recreate or reset the remote value.

## Local workflow after migration

```bash
export CLOUDFLARE_API_TOKEN="<Cloudflare API token>"

# Derive AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_ENDPOINT_URL_S3
# from the cfat_ token as shown in One-time remote-state migration above.

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

Do not create or edit DNS records, zone settings, Origin Rules, Single
Redirects, or the website preview Access application in the Cloudflare
dashboard. Import any existing resource before adding it to this configuration
so Terraform remains its sole owner.
