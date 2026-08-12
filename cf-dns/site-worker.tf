locals {
  site_hostname    = "sshawn9.com"
  site_worker_name = "sshawn9-com"
}

# Only the production Worker owns the stable custom domain. The separate
# sshawn9-com-preview Worker is created by the site deployment workflow and is
# intentionally reachable only through Cloudflare Preview URLs.

data "cloudflare_workers_custom_domains" "site" {
  account_id = var.account_id
  hostname   = local.site_hostname
  service    = local.site_worker_name
  zone_id    = var.zone_id
  max_items  = 2
}

locals {
  site_custom_domain_id = one(data.cloudflare_workers_custom_domains.site.result).id
}

# The domain already exists because Wrangler originally created it. Importing
# it preserves the live mapping while moving long-term ownership to Terraform.
import {
  to = cloudflare_workers_custom_domain.site
  id = "${var.account_id}/${local.site_custom_domain_id}"
}

resource "cloudflare_workers_custom_domain" "site" {
  account_id = var.account_id
  hostname   = local.site_hostname
  service    = local.site_worker_name
  zone_id    = var.zone_id
}
