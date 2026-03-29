resource "cloudflare_ruleset" "origin_rules" {
  count = length(var.origin_rules) > 0 ? 1 : 0

  zone_id = var.zone_id
  name    = "Origin port overrides"
  kind    = "zone"
  phase   = "http_request_origin"

  dynamic "rules" {
    for_each = var.origin_rules
    content {
      action = "route"
      action_parameters {
        origin {
          port = rules.value.port
        }
      }
      expression  = "(http.host eq \"${rules.value.hostname}\")"
      description = rules.key
      enabled     = true
    }
  }
}
