provider "pagerduty" {
  # Token can be provided via variable or PAGERDUTY_TOKEN environment variable
  token = var.pagerduty_token
}
