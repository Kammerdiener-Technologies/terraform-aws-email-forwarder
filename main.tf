resource "random_id" "general_suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {
}

resource "aws_ses_domain_identity" "domain" {
  domain = var.domain_name
}

resource "aws_s3_bucket" "email_forwarding_bucket" {
  bucket = var.bucket_name
  acl    = "private"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowSESPuts",
            "Effect": "Allow",
            "Principal": {
                "Service": "ses.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${var.bucket_name}/*",
            "Condition": {
                "StringEquals": {
                    "aws:Referer": ${var.account_id}
                }
            }
        }
    ]
}
  POLICY

    lifecycle_rule {
    id      = "archive"
    enabled = true

    tags = {
      autoclean = "true"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_iam_role" "email-forwarding" {
  name = "email-forwarding-${random_id.general_suffix.hex}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ses.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "email-forwarding" {
  name = "email-forwarding-${random_id.general_suffix.hex}"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:CreateLogGroup",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "ses:SendRawEmail",
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.email_forwarding_bucket.bucket}/*",
                "arn:aws:ses:us-east-1:${var.account_id}:identity/*"
            ]
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "email-forwarding" {
  role       = aws_iam_role.email-forwarding.name
  policy_arn = aws_iam_policy.email-forwarding.arn
}

resource "aws_cloudwatch_log_group" "email-forwarding-logs" {
  name              = "/aws/lambda/${aws_lambda_function.email-forwarding.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "email-forwarding" {
  function_name = "email-forwarding-${random_id.general_suffix.hex}"
  role          = aws_iam_role.email-forwarding.arn
  handler       = "index.handler"

  source_code_hash = filebase64sha256("${path.module}/code/forward-email.zip")
  filename = "${path.module}/code/forward-email.zip"

  runtime = "nodejs12.x"

  environment {
    variables = {
      emailBucket = aws_s3_bucket.email_forwarding_bucket.bucket
      emailKeyPrefix = ""
      fromEmail = "forward@${var.domain_name}"
      subjectPrefix = "FW: "
      allowPlusSign = false
      forwardMapping = var.forward_mapping
    }
  }
}

resource "aws_lambda_permission" "ses" {
  statement_id   = "AllowExecutionFromSES"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.email-forwarding.function_name
  principal      = "ses.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_ses_receipt_rule_set" "email-forwarding" {
  rule_set_name = "primary"
}

resource "aws_ses_receipt_rule" "email-forwarding" {
  name          = "email-forwarding-${random_id.general_suffix.hex}"
  rule_set_name = aws_ses_receipt_rule_set.email-forwarding.rule_set_name
  recipients    = var.recipients
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name = aws_s3_bucket.email_forwarding_bucket.bucket
    position    = 1
  }

  lambda_action {
    function_arn = aws_lambda_function.email-forwarding.arn
    position = 2
  }
}