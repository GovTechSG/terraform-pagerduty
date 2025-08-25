# SNS Topics Creation
# This creates SNS topics based on teams when create_sns_topics is enabled

# Create team-based SNS topics
locals {
  # Check if pattern uses {service} placeholder for per-service topics
  is_service_based = can(regex("\\{service\\}", var.sns_topic_pattern))
  # For service-based topics: create one topic per service
  service_topics = var.create_sns_topics && local.is_service_based ? {
    for service_key, service in var.services : service_key => replace(
      replace(
        replace(var.sns_topic_pattern, "{service}", service_key),
        "{stage}", var.stage
      ),
      "{team}", lookup(service, "team_name", "default")
    )
  } : {}

  # For team-based topics: create one topic per team (legacy)
  service_teams = distinct([for service in var.services : service.team_name if service.team_name != null])
  team_topics = var.create_sns_topics && !local.is_service_based ? {
    for team in local.service_teams : team => replace(
      replace(
        replace(var.sns_topic_pattern, "{service}", ""),
        "{stage}", var.stage
      ),
      "{team}", team
    )
  } : {}

  # Combine both approaches
  all_topics = merge(local.service_topics, local.team_topics)

  # Clean up topic names (remove double hyphens, leading/trailing hyphens)
  cleaned_topics = {
    for key, topic_name in local.all_topics : key => replace(
      replace(
        replace(topic_name, "--", "-"),
        "/^-+/", ""
      ),
      "/-+$/", ""
    )
  }
}

# Create SNS topics (per service or per team based on pattern) using terraform-aws-modules
module "sns_topics" {
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 6.0"

  for_each = local.cleaned_topics

  name         = each.value
  display_name = local.is_service_based ? "${title(replace(each.key, "_", " "))} Service Alerts - ${upper(var.stage)}" : "${title(replace(each.key, "_", " "))} Alerts - ${upper(var.stage)}"

  # Configure delivery feedback for CloudWatch logging
  http_feedback = var.enable_cloudwatch_logging ? {
    success_role_arn    = aws_iam_role.sns_delivery_status[0].arn
    failure_role_arn    = aws_iam_role.sns_delivery_status[0].arn
    success_sample_rate = 100
  } : {}

  tags = {
    Name      = each.value
    Service   = local.is_service_based ? each.key : null
    Team      = !local.is_service_based ? each.key : lookup(var.services[each.key], "team_name", null)
    Stage     = var.stage
    Purpose   = "PagerDuty Alerts"
    ManagedBy = "Terraform"
  }
}

# Create topic policy to allow CloudWatch to publish
resource "aws_sns_topic_policy" "team_topic_policies" {
  for_each = module.sns_topics

  arn = each.value.topic_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${each.value.topic_name}-policy"
    Statement = [
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = each.value.topic_arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowEventbridgeToPublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = each.value.topic_arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowAccountRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = each.value.topic_arn
      }
    ]
  })
}
