variable "stage" {
  description = "Environment stage (dev, stg, prd)"
  type        = string
}

variable "pagerduty_token" {
  description = "PagerDuty API token"
  type        = string
  sensitive   = true
  default     = null
}

variable "services" {
  description = "Map of PagerDuty services to create"
  type = map(object({
    name              = string
    description       = string
    team_name         = optional(string, null)
    escalation_policy = optional(string, null)
    dependencies      = optional(list(string), []) # List of service keys this service depends on
  }))
  default = {}
}

variable "business_services" {
  description = "Map of business services to create"
  type = map(object({
    name             = string
    description      = string
    team_name        = optional(string, null)
    point_of_contact = optional(string, null)
  }))
  default = {}
}

variable "escalation_policies" {
  description = "Map of escalation policies"
  type = map(object({
    name        = string
    description = string
    teams       = optional(list(string), [])
    escalation_rules = list(object({
      escalation_delay_in_minutes = number
      targets = list(object({
        type = string
        id   = string
      }))
    }))
  }))
  default = {}
}

variable "schedules" {
  description = "Map of on-call schedules"
  type = map(object({
    name        = string
    description = string
    time_zone   = string
    teams       = optional(list(string), [])
    layers = list(object({
      name                         = string
      start                        = string
      rotation_virtual_start       = string
      rotation_turn_length_seconds = number
      users                        = list(string)
    }))
  }))
  default = {}
}

variable "teams" {
  description = "Map of teams to create"
  type = map(object({
    name        = string
    description = string
  }))
  default = {}
}

variable "users" {
  description = "Map of users (will be referenced by email)"
  type = map(object({
    name  = string
    email = string
    role  = optional(string, "user")
  }))
  default = {}
}

variable "default_escalation_policy" {
  description = "Default escalation policy to use if service doesn't specify one"
  type        = string
  default     = "backend_default"
}

variable "integration_type" {
  description = "Type of integration to create (aws_cloudwatch_inbound_integration, generic_events_api_inbound_integration)"
  type        = string
  default     = "aws_cloudwatch_inbound_integration"
}

variable "create_sns_subscriptions" {
  description = "Whether to create SNS topic subscriptions to PagerDuty"
  type        = bool
  default     = true
}

variable "create_sns_topics" {
  description = "Whether to create the SNS topics automatically based on teams"
  type        = bool
  default     = true
}

variable "sns_topic_pattern" {
  description = "Pattern for SNS topic names. Use {service}, {team} and {stage} as placeholders"
  type        = string
  default     = "{service}-{stage}-alerts"
}

variable "existing_sns_topics" {
  description = "Map of existing SNS topic ARNs to subscribe to PagerDuty. If create_sns_topics is true, this will be ignored"
  type        = map(string)
  default     = {}
}

variable "enable_cloudwatch_logging" {
  description = "Whether to enable CloudWatch logging for SNS delivery status"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs for SNS delivery status"
  type        = number
  default     = 14
}

variable "environment" {
  description = "Environment name for tagging and resource naming"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
