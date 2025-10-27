# Lambda Module Usage Examples

This document provides examples of how to use the Lambda module with different IAM policy configurations.

## Basic Usage

Minimal configuration with just the Lambda basic execution role:

```hcl
module "simple_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-deployment-bucket"
  s3_key    = "my-function.zip"
  runtime   = "python3.12"
  handler   = "lambda_function.lambda_handler"
}
```

## Adding Inline IAM Policies

Use `additional_inline_policies` to add custom inline policies to the Lambda execution role:

```hcl
module "lambda_with_inline_policy" {
  source = "./module-sources/lambda"

  s3_bucket = "my-deployment-bucket"
  s3_key    = "my-function.zip"
  runtime   = "python3.12"
  handler   = "lambda_function.lambda_handler"

  # Add custom inline policies
  additional_inline_policies = {
    # Policy for S3 access
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ]
          Resource = "arn:aws:s3:::my-data-bucket"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::my-data-bucket/*"
        }
      ]
    })

    # Policy for DynamoDB access
    dynamodb_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:Query",
            "dynamodb:Scan"
          ]
          Resource = "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable"
        }
      ]
    })
  }
}
```

## Adding Managed IAM Policy ARNs

Use `additional_managed_policy_arns` to attach existing AWS managed or customer-managed policies:

```hcl
module "lambda_with_managed_policies" {
  source = "./module-sources/lambda"

  s3_bucket = "my-deployment-bucket"
  s3_key    = "my-function.zip"
  runtime   = "nodejs20.x"
  handler   = "index.handler"

  # Attach AWS managed policies
  additional_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  ]
}
```

## Combining Both Inline and Managed Policies

You can use both options together:

```hcl
module "lambda_full_example" {
  source = "./module-sources/lambda"

  s3_bucket = "my-deployment-bucket"
  s3_key    = "my-function.zip"
  runtime   = "provided.al2023"
  handler   = "bootstrap"

  timeout_in_seconds = 300
  memory_size        = 1024
  architectures      = ["x86_64"]

  environment_variables = {
    ENVIRONMENT = "production"
    LOG_LEVEL   = "info"
  }

  # Attach managed policies
  additional_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
  ]

  # Add custom inline policies
  additional_inline_policies = {
    # Custom S3 access with specific permissions
    custom_s3_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::my-bucket/uploads/*"
          Condition = {
            StringEquals = {
              "s3:x-amz-server-side-encryption" = "AES256"
            }
          }
        }
      ]
    })

    # SQS permissions
    sqs_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "sqs:SendMessage",
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage"
          ]
          Resource = "arn:aws:sqs:us-east-1:123456789012:my-queue"
        }
      ]
    })
  }

  additional_tags = {
    project     = "my-project"
    environment = "production"
  }
}
```

## Using with Existing IAM Role

If you provide your own IAM role, the additional policies will NOT be attached:

```hcl
module "lambda_with_existing_role" {
  source = "./module-sources/lambda"

  s3_bucket = "my-deployment-bucket"
  s3_key    = "my-function.zip"
  runtime   = "python3.12"
  handler   = "lambda_function.lambda_handler"

  # Use existing IAM role
  iam_role_arn = "arn:aws:iam::123456789012:role/my-existing-lambda-role"

  # These will be IGNORED when iam_role_arn is provided
  additional_managed_policy_arns = [...]  # Not attached
  additional_inline_policies = {...}       # Not attached
}
```

## Real-World Example: Go Lambda with S3 Access

This is the example used for the Go handler in this project:

```hcl
module "go_handler_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-lambda-deployment-packages"
  s3_key    = "go-handler-lambda.zip"

  runtime = "provided.al2023"
  handler = "bootstrap"

  aws_region    = "eu-central-1"
  architectures = ["x86_64"]

  timeout_in_seconds = 100
  memory_size        = 512

  environment_variables = {
    S3_BUCKET_NAME = "my-lambda-deployment-packages"
  }

  additional_inline_policies = {
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ]
          Resource = "arn:aws:s3:::my-lambda-deployment-packages"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:HeadObject"
          ]
          Resource = "arn:aws:s3:::my-lambda-deployment-packages/*"
        }
      ]
    })
  }

  additional_tags = {
    project     = "lambda-use-case"
    environment = "development"
    handler     = "go"
  }
}
```

## Policy Management Best Practices

### When to use Inline Policies vs Managed Policies

**Use Inline Policies when:**
- The policy is specific to this Lambda function
- You need fine-grained, custom permissions
- The policy includes resource-specific ARNs
- You want the policy to be destroyed with the Lambda role

**Use Managed Policies when:**
- Using AWS managed policies (e.g., `AmazonS3ReadOnlyAccess`)
- Sharing policies across multiple Lambda functions
- The policy is managed separately in your organization
- You want to reuse existing customer-managed policies

### Security Best Practices

1. **Principle of Least Privilege**: Only grant permissions the Lambda needs
2. **Avoid Wildcards**: Use specific resource ARNs instead of `*`
3. **Use Conditions**: Add conditions to restrict access further
4. **Separate Policies**: Use multiple smaller policies instead of one large policy
5. **Review Regularly**: Audit policies to remove unused permissions

## Module Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `additional_managed_policy_arns` | `list(string)` | `[]` | List of managed policy ARNs to attach |
| `additional_inline_policies` | `map(string)` | `{}` | Map of inline policies (name => JSON) |

## Notes

- Additional policies are only applied when the module creates the IAM role (when `iam_role_arn` is `null`)
- Inline policy names must be unique within the role
- Each inline policy is limited to 10,240 characters
- You can attach up to 10 managed policies per role
- All policies are automatically destroyed when the Lambda function is destroyed
