variable "zone_id" {
  type = string
}

variable "servers" {
  type        = map(string)
  description = "Server name -> public IP"
}

variable "dns_records" {
  type = map(object({
    server  = string
    type    = optional(string, "A")
    proxied = optional(bool, true)
  }))
  description = "Subdomain -> { server, type, proxied }"
}

variable "ssl_mode" {
  type        = string
  description = "SSL/TLS mode: off, flexible, full, strict"
  default     = "flexible"
}

variable "origin_rules" {
  type = map(object({
    hostname = string
    port     = number
  }))
  description = "Rule description -> { hostname, port }"
  default     = {}
}
