resource "cloudflare_zone_settings_override" "ssl" {
  zone_id = var.zone_id

  settings {
    ssl = var.ssl_mode
  }
}
