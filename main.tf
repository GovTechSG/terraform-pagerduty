# Create teams first
resource "pagerduty_team" "teams" {
  for_each = var.teams

  name        = each.value.name
  description = each.value.description
}

# Create users (these need to be invited manually to PagerDuty first)
data "pagerduty_user" "users" {
  for_each = var.users
  email    = each.value.email
}

# Create schedules for on-call rotations
resource "pagerduty_schedule" "schedules" {
  for_each = var.schedules

  name      = each.value.name
  time_zone = each.value.time_zone
  teams     = length(each.value.teams) > 0 ? [for team_name in each.value.teams : pagerduty_team.teams[team_name].id] : []

  dynamic "layer" {
    for_each = each.value.layers
    content {
      name                         = layer.value.name
      start                        = layer.value.start
      rotation_virtual_start       = layer.value.rotation_virtual_start
      rotation_turn_length_seconds = layer.value.rotation_turn_length_seconds
      users                        = [for user_key in layer.value.users : data.pagerduty_user.users[user_key].id]
    }
  }
}

# Create escalation policies
resource "pagerduty_escalation_policy" "policies" {
  for_each = var.escalation_policies

  name        = each.value.name
  description = each.value.description
  num_loops   = 2
  # Only assign the first team if teams are specified, otherwise no team
  teams = length(each.value.teams) > 0 ? [pagerduty_team.teams[each.value.teams[0]].id] : []

  dynamic "rule" {
    for_each = each.value.escalation_rules
    content {
      escalation_delay_in_minutes = rule.value.escalation_delay_in_minutes

      dynamic "target" {
        for_each = rule.value.targets
        content {
          type = target.value.type
          id   = target.value.type == "schedule_reference" ? pagerduty_schedule.schedules[target.value.id].id : data.pagerduty_user.users[target.value.id].id
        }
      }
    }
  }
}

# Create services
resource "pagerduty_service" "services" {
  for_each = var.services

  name                    = each.value.name
  description             = each.value.description
  auto_resolve_timeout    = 14400 # 4 hours
  acknowledgement_timeout = 1800  # 30 minutes
  escalation_policy = pagerduty_escalation_policy.policies[
    coalesce(each.value.escalation_policy, var.default_escalation_policy)
  ].id

  # Auto-pause incident notifications if too many created
  incident_urgency_rule {
    type    = "constant"
    urgency = "high"
  }
}

# Create integrations for each service (for SNS/CloudWatch)
resource "pagerduty_service_integration" "integrations" {
  for_each = var.services

  name    = "${each.value.name}-sns-integration"
  service = pagerduty_service.services[each.key].id
  vendor  = data.pagerduty_vendor.aws_cloudwatch.id
}

# Create business services (high-level business functions)
resource "pagerduty_business_service" "business_services" {
  for_each = var.business_services

  name             = each.value.name
  description      = each.value.description
  point_of_contact = each.value.point_of_contact
  team             = each.value.team_name != null ? pagerduty_team.teams[each.value.team_name].id : null
}

# Create service dependencies
resource "pagerduty_service_dependency" "dependencies" {
  # Flatten the dependencies to create individual dependency relationships
  for_each = {
    for pair in flatten([
      for service_key, service in var.services : [
        for dep in service.dependencies : {
          dependent_key  = service_key
          supporting_key = dep
          key            = "${service_key}_depends_on_${dep}"
        }
      ]
    ]) : pair.key => pair
  }

  dependency {
    dependent_service {
      id   = pagerduty_service.services[each.value.dependent_key].id
      type = "service"
    }
    supporting_service {
      id   = pagerduty_service.services[each.value.supporting_key].id
      type = "service"
    }
  }
}

# Data source for AWS CloudWatch vendor
data "pagerduty_vendor" "aws_cloudwatch" {
  name = "Amazon CloudWatch"
}
