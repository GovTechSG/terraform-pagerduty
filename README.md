# PagerDuty Terraform Module

This module creates PagerDuty services, escalation policies, schedules, and integrations for alerting.

## Features

- Creates PagerDuty services matching your application names
- Sets up escalation policies with SMS and phone call notifications
- Creates AWS CloudWatch integrations for SNS connectivity
- Supports multiple teams and on-call schedules
- Outputs integration keys for SNS topic subscriptions

## Prerequisites

1. **PagerDuty Account Setup**:
   - Create a PagerDuty account
   - Get an API token: Configuration → API Access → Create New API Token
   - Add team members to PagerDuty (users must exist before running this module)

2. **Environment Variables**:
   ```bash
   export PAGERDUTY_TOKEN="your-api-token-here"
   ```

## Usage

### Basic Example

```hcl
module "pagerduty" {
  source = "${get_repo_root()}/modules//pagerduty"

  stage = "prd"

  # Define your teams
  teams = {
    backend_team = {
      name        = "Backend Team"
      description = "Backend services team"
    }
  }

  # Define your users (must exist in PagerDuty already)
  users = {
    john_doe = {
      name  = "John Doe"
      email = "john.doe@company.com"
    }
    jane_smith = {
      name  = "Jane Smith"
      email = "jane.smith@company.com"
    }
  }

  # Create on-call schedules
  schedules = {
    backend_oncall = {
      name        = "Backend On-Call"
      description = "Backend team on-call rotation"
      time_zone   = "Asia/Singapore"
      teams       = ["backend_team"]  # Optional: assign schedule to team(s)
      layers = [{
        name                         = "Daily Rotation"
        start                       = "2024-01-01T09:00:00+08:00"
        rotation_virtual_start      = "2024-01-01T09:00:00+08:00"
        rotation_turn_length_seconds = 86400  # 24 hours
        users                       = ["john_doe", "jane_smith"]
      }]
    }
  }

  # Create escalation policies
  escalation_policies = {
    default = {
      name        = "Default Escalation"
      description = "Standard escalation policy with SMS and phone calls"
      teams       = ["backend_team"]
      escalation_rules = [
        {
          escalation_delay_in_minutes = 5
          targets = [{
            type = "schedule_reference"
            id   = "backend_oncall"
          }]
        },
        {
          escalation_delay_in_minutes = 15
          targets = [{
            type = "user_reference"
            id   = "john_doe"
          }]
        }
      ]
    }
  }

  # Define your services
  services = {
    login_api = {
      name        = "Login API"
      description = "Authentication service"
      team_name   = "backend_team"
    }
  }
}
```

### Integration with SNS

After applying this module, use the integration keys in your SNS topic subscriptions:

```hcl
# In your SNS topic configuration
resource "aws_sns_topic_subscription" "pagerduty" {
  for_each = module.pagerduty.service_integration_keys

  topic_arn              = aws_sns_topic.alerts.arn
  protocol              = "https"
  endpoint              = each.value.integration_url
  endpoint_auto_confirms = true
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| stage | Environment stage | `string` | n/a | yes |
| services | Map of PagerDuty services to create | `map(object)` | `{}` | no |
| teams | Map of teams to create | `map(object)` | `{}` | no |
| users | Map of users to reference | `map(object)` | `{}` | no |
| schedules | Map of on-call schedules | `map(object)` | `{}` | no |
| escalation_policies | Map of escalation policies | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| services | Created PagerDuty services |
| service_integration_keys | Integration keys for SNS (sensitive) |
| escalation_policies | Created escalation policies |
| schedules | Created schedules |
| teams | Created teams |

## Manual Steps Required

1. **Add Users to PagerDuty**: Users must be manually invited to your PagerDuty account first
2. **Configure Notification Methods**: Set up SMS and phone numbers for each user in PagerDuty UI
3. **Test Integrations**: Send test alerts to verify SNS → PagerDuty flow works

## Notification Setup (Manual)

For each user in PagerDuty:
1. Go to My Profile → Contact Information
2. Add phone number for SMS notifications
3. Add phone number for voice calls
4. Set notification rules:
   - Immediately: Push notification
   - After 2 minutes: SMS
   - After 5 minutes: Phone call
   - After 10 minutes: SMS + Phone call

## Example Directory Structure

```
account/production/app/pagerduty/
└── terragrunt.hcl
```
