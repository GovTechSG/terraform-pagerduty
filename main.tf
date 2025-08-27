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

# Data source for any escalation policy referenced by services but not defined locally
data "pagerduty_escalation_policy" "external_policies" {
  for_each = toset([
    for service_key, service in var.services : service.escalation_policy
    if service.escalation_policy != null && !contains(keys(var.escalation_policies), service.escalation_policy)
  ])
  name = each.value
}

# Create services
resource "pagerduty_service" "services" {
  for_each = var.services

  name                    = each.value.name
  description             = each.value.description
  auto_resolve_timeout    = 14400 # 4 hours
  acknowledgement_timeout = 1800  # 30 minutes

  escalation_policy = (
    # If escalation_policy is specified and exists locally, use local policy
    each.value.escalation_policy != null && contains(keys(var.escalation_policies), each.value.escalation_policy)
    ? pagerduty_escalation_policy.policies[each.value.escalation_policy].id
    # If escalation_policy is specified but not local, use external data source
    : each.value.escalation_policy != null
    ? data.pagerduty_escalation_policy.external_policies[each.value.escalation_policy].id
    # If no escalation_policy specified and default exists locally, use default
    : var.default_escalation_policy != null && contains(keys(var.escalation_policies), var.default_escalation_policy)
    ? pagerduty_escalation_policy.policies[var.default_escalation_policy].id
    # If default is external, look it up
    : var.default_escalation_policy != null
    ? data.pagerduty_escalation_policy.external_policies[var.default_escalation_policy].id
    # This should not happen if configuration is correct
    : null
  )

  # Service-specific incident urgency rules
  incident_urgency_rule {
    type = each.value.urgency_config.type

    # For constant urgency
    urgency = each.value.urgency_config.type == "constant" ? each.value.urgency_config.urgency : null

    # For support hours based urgency
    dynamic "during_support_hours" {
      for_each = each.value.urgency_config.type == "use_support_hours" && each.value.urgency_config.during_support_hours != null ? [each.value.urgency_config.during_support_hours] : []
      content {
        type    = during_support_hours.value.type
        urgency = during_support_hours.value.urgency
      }
    }

    dynamic "outside_support_hours" {
      for_each = each.value.urgency_config.type == "use_support_hours" && each.value.urgency_config.outside_support_hours != null ? [each.value.urgency_config.outside_support_hours] : []
      content {
        type    = outside_support_hours.value.type
        urgency = outside_support_hours.value.urgency
      }
    }
  }

  # Service-specific support hours
  dynamic "support_hours" {
    for_each = each.value.urgency_config.support_hours != null ? [each.value.urgency_config.support_hours] : []
    content {
      type         = support_hours.value.type
      time_zone    = support_hours.value.time_zone
      start_time   = support_hours.value.start_time
      end_time     = support_hours.value.end_time
      days_of_week = support_hours.value.days_of_week
    }
  }
}

# Create integrations for each service (for SNS/CloudWatch)
resource "pagerduty_service_integration" "integrations" {
  for_each = var.services

  name    = "${each.value.name}-sns-integration"
  service = pagerduty_service.services[each.key].id
  vendor  = data.pagerduty_vendor.aws_cloudwatch.id
}

# Create service-specific event rules
resource "pagerduty_service_event_rule" "service_rules" {
  # Flatten the event rules to create individual rule resources
  for_each = {
    for pair in flatten([
      for service_key, service in var.services : [
        for rule_index, rule in service.event_rules : {
          service_key = service_key
          rule_index  = rule_index
          rule        = rule
          key         = "${service_key}_rule_${rule_index}"
        }
      ]
    ]) : pair.key => pair
  }

  service  = pagerduty_service.services[each.value.service_key].id
  position = each.value.rule.position
  disabled = each.value.rule.disabled

  # Build conditions block
  conditions {
    operator = each.value.rule.conditions.operator

    dynamic "subconditions" {
      for_each = each.value.rule.conditions.subconditions
      content {
        operator = subconditions.value.operator
        parameter {
          value = subconditions.value.parameter.value
          path  = subconditions.value.parameter.path
        }
      }
    }
  }

  # Build actions block
  actions {
    # Set priority if specified
    dynamic "priority" {
      for_each = each.value.rule.actions.priority != null ? [each.value.rule.actions.priority] : []
      content {
        value = priority.value
      }
    }

    # Add annotation if specified
    dynamic "annotate" {
      for_each = each.value.rule.actions.annotate != null ? [each.value.rule.actions.annotate] : []
      content {
        value = annotate.value
      }
    }

    # Suppress alerts if specified
    dynamic "suppress" {
      for_each = each.value.rule.actions.suppress ? [1] : []
      content {
        value                 = true
        threshold_value       = each.value.rule.actions.suppress_config != null ? each.value.rule.actions.suppress_config.threshold_value : null
        threshold_time_unit   = each.value.rule.actions.suppress_config != null ? each.value.rule.actions.suppress_config.threshold_time_unit : null
        threshold_time_amount = each.value.rule.actions.suppress_config != null ? each.value.rule.actions.suppress_config.threshold_time_amount : null
      }
    }
  }

  # Add time frame restrictions if specified
  dynamic "time_frame" {
    for_each = each.value.rule.time_frame != null ? [each.value.rule.time_frame] : []
    content {
      dynamic "scheduled_weekly" {
        for_each = time_frame.value.scheduled_weekly != null ? [time_frame.value.scheduled_weekly] : []
        content {
          weekdays   = scheduled_weekly.value.weekdays
          start_time = scheduled_weekly.value.start_time
          duration   = scheduled_weekly.value.duration
          timezone   = scheduled_weekly.value.timezone
        }
      }
    }
  }
}

# Create business services (high-level business functions)
resource "pagerduty_business_service" "business_services" {
  for_each = var.business_services

  name             = each.value.name
  description      = each.value.description
  point_of_contact = each.value.point_of_contact
  team             = each.value.team_name != null ? pagerduty_team.teams[each.value.team_name].id : null
}

# Data source for any services referenced in dependencies but not defined locally
data "pagerduty_service" "external_services" {
  for_each = toset(flatten([
    for service_key, service in var.services : [
      for dep in service.dependencies : dep
      if !contains(keys(var.services), dep)
    ]
  ]))
  name = each.value
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
      id   = contains(keys(var.services), each.value.supporting_key) ? pagerduty_service.services[each.value.supporting_key].id : data.pagerduty_service.external_services[each.value.supporting_key].id
      type = "service"
    }
  }
}

# Data source for AWS CloudWatch vendor
data "pagerduty_vendor" "aws_cloudwatch" {
  name = "Amazon CloudWatch"
}
