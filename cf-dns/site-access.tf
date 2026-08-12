resource "cloudflare_zero_trust_access_identity_provider" "site_previews" {
  account_id = var.account_id
  name       = "Cloudflare account"
  type       = "cloudflare"

  config = {
    restrict_to_account_members = true
  }
}

resource "cloudflare_zero_trust_access_policy" "site_previews" {
  account_id       = var.account_id
  name             = "Allow Cloudflare account members to website previews"
  decision         = "allow"
  session_duration = "24h"

  include = [{
    cloudflare_account_member = {
      account_id = var.account_id
    }
  }]
}

resource "cloudflare_zero_trust_access_application" "site_previews" {
  account_id                = var.account_id
  name                      = "sshawn9.com previews"
  type                      = "self_hosted"
  session_duration          = "24h"
  app_launcher_visible      = false
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.site_previews.id]
  auto_redirect_to_identity = true

  destinations = [
    {
      type = "public"
      uri  = "*-${local.site_worker_name}.${local.workers_dev_account_domain}/*"
    },
    {
      type = "public"
      uri  = "${local.site_preview_worker_name}.${local.workers_dev_account_domain}/*"
    },
    {
      type = "public"
      uri  = "*-${local.site_preview_worker_name}.${local.workers_dev_account_domain}/*"
    },
  ]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.site_previews.id
    precedence = 1
  }]
}
