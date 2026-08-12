variable "account_id" {
  type        = string
  description = "Cloudflare account ID derived from the account-owned API token"

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character lowercase hexadecimal Cloudflare account ID."
  }
}

variable "zone_id" {
  type        = string
  description = "Cloudflare zone ID for sshawn9.com"

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character lowercase hexadecimal Cloudflare zone ID."
  }
}
