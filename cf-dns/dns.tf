resource "cloudflare_record" "dns" {
  for_each = var.dns_records

  zone_id = var.zone_id
  name    = each.key
  content = var.servers[each.value.server]
  type    = each.value.type
  proxied = each.value.proxied
}
