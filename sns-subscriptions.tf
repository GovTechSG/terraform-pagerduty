# SNS Topic Subscriptions to PagerDuty
# This creates the actual connection between SNS topics and PagerDuty services

# Generate SNS topic ARNs based on configuration
locals {
  # Determine SNS topic for each service
  sns_topic_arns = var.create_sns_subscriptions ? {
    for service_key, service in var.services : service_key =>
    var.create_sns_topics ?
    # Use auto-created topic from the module (service-based or team-based)
    module.sns_topics[service_key].topic_arn :
    length(var.existing_sns_topics) > 0 && contains(keys(var.existing_sns_topics), service_key) ?
    # Use existing topic if specified
    var.existing_sns_topics[service_key] :
    # Generate topic ARN based on pattern (fallback)
    "arn:aws:sns:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:${
      replace(
        replace(
          replace(var.sns_topic_pattern, "{service}", service_key),
          "{stage}", var.stage
        ),
        "{team}", lookup(service, "team_name", "default")
      )
    }"
  } : {} # Group services by SNS topic (for shared topics)
  topic_to_services = var.create_sns_subscriptions ? {
    for topic_arn in distinct(values(local.sns_topic_arns)) : topic_arn => [
      for service_key, service_topic in local.sns_topic_arns : service_key
      if service_topic == topic_arn
    ]
  } : {}
}

# SNS subscriptions for incident alerts (using CloudWatch integration)
# Each service gets its own subscription to the team SNS topic
# PagerDuty will route based on the service's unique integration key
resource "aws_sns_topic_subscription" "pagerduty_incidents" {
  for_each = local.sns_topic_arns

  topic_arn              = each.value
  protocol               = "https"
  endpoint               = "https://events.pagerduty.com/integration/${pagerduty_service_integration.integrations[each.key].integration_key}/enqueue"
  endpoint_auto_confirms = true

  depends_on = [pagerduty_service_integration.integrations]
}

# Data sources for AWS account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
