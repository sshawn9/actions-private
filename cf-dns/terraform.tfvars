# ============================================================
#  All config lives here. Edit this file, push, done.
# ============================================================

# Cloudflare Zone ID (dashboard -> domain overview -> right sidebar)
zone_id = "2cbfbc36ae05bc041b712442e2f7b584"

# -------------------- SSL/TLS --------------------
# Zone-wide mode: "off" | "flexible" | "full" | "strict"
# flexible = user-to-CF encrypted, CF-to-origin plaintext (no cert needed)
# full     = encrypted end-to-end (origin needs cert, self-signed OK)
# strict   = encrypted end-to-end (origin needs valid cert)
ssl_mode = "flexible"

# -------------------- Servers --------------------
servers = {
  # hk1 = "1.2.3.4"
  rn-2c = "104.129.51.144"
}

# -------------------- DNS Records --------------------
# key = subdomain, server = name from servers above
# defaults: type = "A", proxied = true
dns_records = {
  # blog    = { server = "hk1" }
  # api     = { server = "hk1", proxied = false }
  easytier  = { server = "rn-2c" }
  et-config = { server = "rn-2c" }
}

# -------------------- Origin Rules --------------------
# Override destination port for proxied records (not needed for 80/443)
origin_rules = {
  "EasyTier Web panel"     = { hostname = "easytier.sshawn9.com",  port = 11212 }
  "EasyTier Config server" = { hostname = "et-config.sshawn9.com", port = 22020 }
}
