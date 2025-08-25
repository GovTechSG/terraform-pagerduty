output "services" {
  description = "Created PagerDuty services"
  value = {
    for k, v in pagerduty_service.services : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "service_integration_keys" {
  description = "Integration keys for SNS subscriptions"
  value = {
    for k, v in pagerduty_service_integration.integrations : k => {
      integration_key = v.integration_key
      service_name    = pagerduty_service.services[k].name
    }
  }
  sensitive = true
}

output "sns_subscriptions" {
  description = "Created SNS subscriptions to PagerDuty"
  value = {
    for k, v in aws_sns_topic_subscription.pagerduty_incidents : k => {
      subscription_arn = v.arn
      topic_arn        = v.topic_arn
      service_name     = pagerduty_service.services[k].name
    }
  }
}

output "sns_topics" {
  description = "Created SNS topics for team-based alerting"
  value = var.create_sns_topics ? {
    for team, topic in module.sns_topics : team => {
      name = topic.topic_name
      arn  = topic.topic_arn
    }
  } : {}
}

output "sns_topic_arns" {
  description = "Map of service to SNS topic ARN"
  value       = local.sns_topic_arns
}

output "topic_to_services" {
  description = "Map of SNS topic ARN to list of services using it"
  value       = local.topic_to_services
}

output "escalation_policies" {
  description = "Created escalation policies"
  value = {
    for k, v in pagerduty_escalation_policy.policies : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "schedules" {
  description = "Created schedules"
  value = {
    for k, v in pagerduty_schedule.schedules : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "teams" {
  description = "Created teams"
  value = {
    for k, v in pagerduty_team.teams : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "business_services" {
  description = "Created business services"
  value = {
    for k, v in pagerduty_business_service.business_services : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "service_dependencies" {
  description = "Created service dependencies"
  value = {
    for k, v in pagerduty_service_dependency.dependencies : k => {
      id = v.id
    }
  }
}
