# CloudWatch Log Groups for SNS delivery status logging
resource "aws_cloudwatch_log_group" "sns_success" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name              = "/aws/sns/pagerduty-success-${var.stage}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(var.common_tags, {
    Name        = "pagerduty-sns-success-${var.stage}-logs"
    Component   = "logging"
    Environment = var.environment
  })
}

resource "aws_cloudwatch_log_group" "sns_failure" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name              = "/aws/sns/pagerduty-failure-${var.stage}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(var.common_tags, {
    Name        = "pagerduty-sns-failure-${var.stage}-logs"
    Component   = "logging"
    Environment = var.environment
  })
}

# IAM role for SNS delivery status logging
resource "aws_iam_role" "sns_delivery_status" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name = "service-pagerduty-sns-delivery-status-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "pagerduty-sns-delivery-status"
    Component   = "iam-role"
    Environment = var.environment
  })
}

# IAM policy for SNS CloudWatch logging
resource "aws_iam_policy" "sns_cloudwatch_logging" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name        = "service-pagerduty-sns-cloudwatch-logging-${var.environment}"
  description = "Allow SNS to write delivery status logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutMetricFilter",
          "logs:PutRetentionPolicy"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sns/pagerduty-*"
        ]
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "pagerduty-sns-cloudwatch-logging"
    Component   = "iam-policy"
    Environment = var.environment
  })
}

# Attach CloudWatch logging policy to SNS delivery status role
resource "aws_iam_role_policy_attachment" "sns_cloudwatch_logging" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  role       = aws_iam_role.sns_delivery_status[0].name
  policy_arn = aws_iam_policy.sns_cloudwatch_logging[0].arn
}

# SNS delivery status logging is now handled natively by the terraform-aws-modules/sns module
# The http_feedback configuration in sns-topics.tf automatically configures
# the delivery status logging attributes using the IAM role above.
