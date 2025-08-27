# Example: Service-Specific Event Rules Configuration

This example shows how to configure different priority handling for different services using SNS payload-based routing.

## terraform.tfvars

```hcl
services = {
  # Critical production API service
  "api-gateway" = {
    name              = "API Gateway"
    description       = "Mission-critical API gateway service"
    escalation_policy = "critical-escalation"
    dependencies      = []

    # Always high urgency for critical service
    urgency_config = {
      type    = "constant"
      urgency = "high"
    }

    # Event rules for different severity levels
    event_rules = [
      {
        name     = "Critical Production Alerts"
        position = 0
        conditions = {
          operator = "and"
          subconditions = [
            {
              operator = "contains"
              parameter = {
                value = "critical"
                path  = "payload.severity"
              }
            },
            {
              operator = "contains"
              parameter = {
                value = "production"
                path  = "payload.environment"
              }
            }
          ]
        }
        actions = {
          priority = "P1"
          annotate = "🚨 CRITICAL PRODUCTION: Immediate attention required"
        }
      },
      {
        name     = "Warning Alerts"
        position = 1
        conditions = {
          operator = "and"
          subconditions = [
            {
              operator = "contains"
              parameter = {
                value = "warning"
                path  = "payload.severity"
              }
            }
          ]
        }
        actions = {
          priority = "P2"
          annotate = "⚠️ WARNING: Monitor closely"
        }
      }
    ]
  }

  # Internal monitoring service with business hours support
  "monitoring-service" = {
    name              = "Internal Monitoring"
    description       = "Internal monitoring and observability"
    escalation_policy = "standard-escalation"
    dependencies      = []

    # Business hours based urgency
    urgency_config = {
      type = "use_support_hours"
      during_support_hours = {
        type    = "constant"
        urgency = "high"
      }
      outside_support_hours = {
        type    = "constant"
        urgency = "low"
      }
      support_hours = {
        type         = "fixed_time_per_day"
        time_zone    = "Asia/Singapore"
        start_time   = "09:00:00"
        end_time     = "18:00:00"
        days_of_week = [1, 2, 3, 4, 5] # Monday to Friday
      }
    }

    # Different rules for internal monitoring
    event_rules = [
      {
        name     = "Business Hours Alerts"
        position = 0
        conditions = {
          operator = "or"
          subconditions = [
            {
              operator = "contains"
              parameter = {
                value = "warning"
                path  = "payload.severity"
              }
            },
            {
              operator = "contains"
              parameter = {
                value = "info"
                path  = "payload.severity"
              }
            }
          ]
        }
        actions = {
          priority = "P3"
          annotate = "📊 Internal monitoring - business hours"
        }
        time_frame = {
          scheduled_weekly = {
            weekdays   = [1, 2, 3, 4, 5]  # Monday to Friday
            start_time = "09:00:00"
            duration   = 32400             # 9 hours (9 AM to 6 PM)
            timezone   = "Asia/Singapore"
          }
        }
      },
      {
        name     = "Suppress Low Priority After Hours"
        position = 1
        conditions = {
          operator = "and"
          subconditions = [
            {
              operator = "contains"
              parameter = {
                value = "info"
                path  = "payload.severity"
              }
            }
          ]
        }
        actions = {
          suppress = true
          suppress_config = {
            threshold_value      = 5
            threshold_time_unit  = "minutes"
            threshold_time_amount = 30
          }
        }
      }
    ]
  }

  # Development environment service
  "dev-api" = {
    name              = "Development API"
    description       = "Development environment API"
    escalation_policy = "dev-escalation"
    dependencies      = []

    # Low urgency for dev environment
    urgency_config = {
      type    = "constant"
      urgency = "low"
    }

    # Suppress all but critical alerts in dev
    event_rules = [
      {
        name     = "Dev Critical Only"
        position = 0
        conditions = {
          operator = "and"
          subconditions = [
            {
              operator = "contains"
              parameter = {
                value = "development"
                path  = "payload.environment"
              }
            },
            {
              operator = "not_contains"
              parameter = {
                value = "critical"
                path  = "payload.severity"
              }
            }
          ]
        }
        actions = {
          suppress = true
          annotate = "Dev environment - suppressed unless critical"
        }
      }
    ]
  }
}

escalation_policies = {
  "critical-escalation" = {
    name        = "Critical Services"
    description = "Immediate escalation for critical services"
    teams       = ["platform-team"]
    escalation_rules = [
      {
        escalation_delay_in_minutes = 5
        targets = [
          { type = "schedule_reference", id = "primary-oncall" }
        ]
      },
      {
        escalation_delay_in_minutes = 5
        targets = [
          { type = "schedule_reference", id = "secondary-oncall" }
        ]
      }
    ]
  }

  "standard-escalation" = {
    name        = "Standard Escalation"
    description = "Normal escalation for business hours"
    teams       = ["platform-team"]
    escalation_rules = [
      {
        escalation_delay_in_minutes = 30
        targets = [
          { type = "schedule_reference", id = "primary-oncall" }
        ]
      }
    ]
  }

  "dev-escalation" = {
    name        = "Development Escalation"
    description = "Low priority escalation for dev environments"
    teams       = ["dev-team"]
    escalation_rules = [
      {
        escalation_delay_in_minutes = 60
        targets = [
          { type = "user_reference", id = "dev_lead" }
        ]
      }
    ]
  }
}
```

## SNS Message Examples

### Critical Production Alert
```json
{
  "default": "Critical alert in production API",
  "AlarmName": "HighErrorRate",
  "AlarmDescription": "Error rate exceeded 5%",
  "AWSAccountId": "123456789012",
  "Region": "ap-southeast-1",
  "severity": "critical",
  "environment": "production",
  "service": "api-gateway",
  "priority": "P1"
}
```

### Warning Alert
```json
{
  "default": "Warning: High CPU usage",
  "AlarmName": "HighCPUUsage",
  "AlarmDescription": "CPU usage exceeded 80%",
  "severity": "warning",
  "environment": "production",
  "service": "api-gateway",
  "priority": "P2"
}
```

### Development Alert (will be suppressed)
```json
{
  "default": "Info: Deployment completed",
  "severity": "info",
  "environment": "development",
  "service": "dev-api",
  "priority": "P4"
}
```

## Key Features

- **Per-service event rules**: Each service can have its own routing logic
- **SNS payload-based routing**: Route alerts based on severity, environment, priority, etc.
- **Time-based restrictions**: Apply rules only during business hours
- **Alert suppression**: Suppress low-priority alerts after hours or in dev environments
- **Priority override**: Set different PagerDuty priorities (P1-P5) based on content
- **Custom annotations**: Add context-specific annotations to alerts
- **Flexible urgency rules**: Constant vs. support hours based urgency per service
