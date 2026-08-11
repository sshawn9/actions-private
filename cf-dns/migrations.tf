# Preserve the existing DNS record identities while moving from the provider
# v4 resource and the generic for_each map to explicit provider v5 resources.
moved {
  from = cloudflare_record.dns["easytier"]
  to   = cloudflare_dns_record.easytier
}

moved {
  from = cloudflare_record.dns["et-config"]
  to   = cloudflare_dns_record.et_config
}

# Removing count from the ruleset gives it a stable singleton address.
moved {
  from = cloudflare_ruleset.origin_rules[0]
  to   = cloudflare_ruleset.origin_rules
}

# Provider v5 replaced the aggregate override with one resource per setting.
# The legacy state entry must be forgotten before planning; the existing API
# setting is then adopted without changing its remote value.
removed {
  from = cloudflare_zone_settings_override.ssl

  lifecycle {
    destroy = false
  }
}

import {
  to = cloudflare_zone_setting.ssl
  id = "${var.zone_id}/ssl"
}
