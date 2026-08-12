locals {
  site_hostname              = "sshawn9.com"
  site_worker_name           = "sshawn9-com"
  site_preview_worker_name   = "sshawn9-com-preview"
  workers_dev_account_domain = "regiprotonregi.workers.dev"
}

# Only the production Worker owns the stable custom domain. The separate
# sshawn9-com-preview Worker and both Workers' version URLs are protected by
# the Access application declared in site-access.tf.

resource "cloudflare_workers_custom_domain" "site" {
  account_id = var.account_id
  hostname   = local.site_hostname
  service    = local.site_worker_name
  zone_id    = var.zone_id
}
