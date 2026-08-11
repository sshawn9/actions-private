resource "cloudflare_dns_record" "easytier" {
  zone_id = var.zone_id
  name    = "easytier.sshawn9.com"
  content = "104.129.51.144"
  type    = "A"
  ttl     = 1
  proxied = true
  comment = "EasyTier web panel"
}

resource "cloudflare_dns_record" "et_config" {
  zone_id = var.zone_id
  name    = "et-config.sshawn9.com"
  content = "104.129.51.144"
  type    = "A"
  ttl     = 1
  proxied = true
  comment = "EasyTier config server"
}

# Cloudflare's documented originless-hostname pattern. The Single Redirect
# rule runs at the edge, so Cloudflare never connects to this reserved address.
resource "cloudflare_dns_record" "www_redirect" {
  zone_id = var.zone_id
  name    = "www.sshawn9.com"
  content = "192.0.2.1"
  type    = "A"
  ttl     = 1
  proxied = true
  comment = "Originless hostname for www to apex redirect"
}
