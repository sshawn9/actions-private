resource "cloudflare_ruleset" "origin_rules" {
  zone_id     = var.zone_id
  name        = "Origin port overrides"
  description = "Route proxied service hostnames to non-standard origin ports"
  kind        = "zone"
  phase       = "http_request_origin"

  rules = [
    {
      ref         = "easytier_config_server"
      description = "EasyTier Config server"
      expression  = "(http.host eq \"et-config.sshawn9.com\")"
      action      = "route"
      enabled     = true
      action_parameters = {
        origin = {
          port = 22020
        }
      }
    },
    {
      ref         = "easytier_web_panel"
      description = "EasyTier Web panel"
      expression  = "(http.host eq \"easytier.sshawn9.com\")"
      action      = "route"
      enabled     = true
      action_parameters = {
        origin = {
          port = 11212
        }
      }
    },
  ]
}

resource "cloudflare_ruleset" "single_redirects" {
  zone_id     = var.zone_id
  name        = "Single Redirects"
  description = "Canonical hostname redirects"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [
    {
      ref         = "redirect_www_to_apex"
      description = "Redirect www.sshawn9.com to sshawn9.com"
      expression  = "(http.host eq \"www.sshawn9.com\")"
      action      = "redirect"
      enabled     = true
      action_parameters = {
        from_value = {
          status_code           = 308
          preserve_query_string = true
          target_url = {
            expression = "concat(\"https://sshawn9.com\", http.request.uri.path)"
          }
        }
      }
    },
  ]
}
