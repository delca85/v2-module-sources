# Lambda Module - Test Invocations Feature

The Lambda module now supports automatic test invocations after deployment. This feature allows you to verify that your Lambda function is working correctly by automatically invoking it with test payloads.

## Overview

When you deploy a Lambda function using this module, you can optionally configure test invocations that will run automatically after the function is created or updated. This is useful for:

- **Validation**: Verify the Lambda has correct permissions
- **Integration Testing**: Ensure the function works with other AWS services
- **Smoke Testing**: Quick sanity check after deployment
- **CI/CD**: Automated testing in deployment pipelines

## Basic Usage

Add test invocations to your module configuration:

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-bucket"
  s3_key    = "function.zip"
  runtime   = "python3.12"
  handler   = "index.handler"

  # Configure test invocations
  test_invocations = [
    {
      name    = "health-check"
      payload = jsonencode({ action = "ping" })
    }
  ]
}
```

## Configuration Variables

### `test_invocations`

List of test invocations to run after Lambda deployment.

**Type**: `list(object({ name = string, payload = string }))`
**Default**: `[]` (no invocations)
**Required**: No

Each invocation requires:
- **name**: Unique identifier for this test (used in logs and response files)
- **payload**: JSON string representing the event to send to the Lambda

**Example**:
```hcl
test_invocations = [
  {
    name    = "test1"
    payload = jsonencode({ key = "value" })
  },
  {
    name    = "test2"
    payload = jsonencode({ action = "list", param = 123 })
  }
]
```

### `invoke_on_every_apply`

Controls when test invocations are triggered.

**Type**: `bool`
**Default**: `false`
**Required**: No

- **`true`**: Invocations run on every `terraform apply`
- **`false`**: Invocations only run when the Lambda function changes

**Example**:
```hcl
invoke_on_every_apply = true  # Always test on apply
```

## Complete Example

Here's a full example for a Go Lambda that tests S3 operations:

```hcl
module "go_handler_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-lambda-deployment-packages"
  s3_key    = "go-handler-lambda.zip"
  runtime   = "provided.al2023"
  handler   = "bootstrap"

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
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
          Resource = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
        }
      ]
    })
  }

  # Define test invocations
  test_invocations = [
    {
      name    = "list"
      payload = jsonencode({ action = "list" })
    },
    {
      name    = "write"
      payload = jsonencode({ action = "write", object_key = "test.txt" })
    },
    {
      name    = "read"
      payload = jsonencode({ action = "read", object_key = "test.txt" })
    }
  ]

  invoke_on_every_apply = true
}
```

## How It Works

### Execution Flow

1. **Deploy Lambda**: Terraform creates/updates the Lambda function
2. **Wait for Completion**: `depends_on` ensures Lambda is ready
3. **Run Invocations**: For each test in `test_invocations`:
   - Invoke Lambda using AWS CLI
   - Save response to `/tmp/lambda-{name}-response.json`
   - Display response in Terraform output
4. **Continue Deployment**: Terraform proceeds with remaining resources

### Under the Hood

The module creates `null_resource` blocks that use `local-exec` provisioners:

```hcl
resource "null_resource" "test_invocations" {
  for_each = { for inv in var.test_invocations : inv.name => inv }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda invoke \
        --function-name ${aws_lambda_function.function.function_name} \
        --payload '${each.value.payload}' \
        --region ${var.aws_region} \
        /tmp/lambda-${each.key}-response.json
    EOT
  }
}
```

## Viewing Invocation Results

### During Deployment

Results are printed to the console during `terraform apply`:

```
null_resource.test_invocations["list"] (local-exec): Invoking Lambda 'my-function-abc123' with test: list
null_resource.test_invocations["list"] (local-exec): Response from list:
null_resource.test_invocations["list"] (local-exec): {
null_resource.test_invocations["list"] (local-exec):   "message": "Success",
null_resource.test_invocations["list"] (local-exec):   "status_code": 200
null_resource.test_invocations["list"] (local-exec): }
```

### Response Files

Each invocation saves its response to a file:

```bash
# View response from "list" test
cat /tmp/lambda-list-response.json | jq .

# View response from "write" test
cat /tmp/lambda-write-response.json | jq .
```

### Terraform Output

Check the status of invocations:

```bash
terraform output test_invocations
```

Output:
```json
{
  "list" = {
    "id" = "8934567890123456789"
    "response_file" = "/tmp/lambda-list-response.json"
  }
  "write" = {
    "id" = "1234567890123456789"
    "response_file" = "/tmp/lambda-write-response.json"
  }
}
```

## Advanced Usage

### Multiple Complex Invocations

```hcl
test_invocations = [
  {
    name = "create-user"
    payload = jsonencode({
      action = "create"
      user = {
        name  = "test-user"
        email = "test@example.com"
      }
    })
  },
  {
    name = "query-database"
    payload = jsonencode({
      action = "query"
      table  = "users"
      limit  = 10
    })
  },
  {
    name = "send-notification"
    payload = jsonencode({
      action  = "notify"
      channel = "email"
      message = "Deployment successful"
    })
  }
]
```

### Conditional Invocations

Only run tests in development environment:

```hcl
locals {
  is_dev = var.environment == "development"
}

module "my_lambda" {
  source = "./module-sources/lambda"

  # ... other configuration ...

  test_invocations = local.is_dev ? [
    {
      name    = "smoke-test"
      payload = jsonencode({ action = "test" })
    }
  ] : []
}
```

### Sequential Dependencies

Since invocations use `for_each`, they run in parallel by default. If you need sequential execution, use a single invocation that handles multiple operations, or manage order in your Lambda code.

## Disabling Test Invocations

To deploy without running tests:

### Option 1: Remove from Configuration

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"
  # ... configuration ...
  # Don't include test_invocations
}
```

### Option 2: Use Empty List

```hcl
test_invocations = []  # No tests
```

### Option 3: Terraform Targeting

Deploy Lambda without triggering tests:

```bash
terraform apply -target=module.my_lambda.aws_lambda_function.function
```

## Requirements

### Prerequisites

- **AWS CLI**: Must be installed and available in PATH
- **AWS Credentials**: Must be configured with appropriate permissions
- **jq** (optional): For pretty-printing JSON responses

Install jq:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Amazon Linux
sudo yum install jq
```

### Required IAM Permissions

The Terraform executor needs permission to invoke Lambda:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:*:*:function:*"
    }
  ]
}
```

## Troubleshooting

### Error: "aws: command not found"

**Solution**: Install AWS CLI or ensure it's in your PATH.

### Error: "Unable to locate credentials"

**Solution**: Configure AWS credentials:
```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

### Invocation Times Out

**Solution**: Increase Lambda timeout or check function execution time:
```hcl
timeout_in_seconds = 300  # 5 minutes
```

### Response Shows Error

Check the response file for details:
```bash
cat /tmp/lambda-{name}-response.json | jq .
```

Common Lambda errors:
- **AccessDenied**: Lambda lacks IAM permissions
- **ResourceNotFound**: Resource (e.g., S3 bucket) doesn't exist
- **Runtime Error**: Code bug or missing dependencies

### Tests Don't Re-run

If `invoke_on_every_apply = false`, tests only run on Lambda changes.

**Solution**: Either:
1. Set `invoke_on_every_apply = true`
2. Manually trigger: `terraform apply -replace=module.my_lambda.null_resource.test_invocations[\"test-name\"]`

## Best Practices

### 1. Use Descriptive Names

```hcl
# Good
test_invocations = [
  { name = "verify-s3-read-permissions", payload = "..." },
  { name = "check-database-connection", payload = "..." }
]

# Bad
test_invocations = [
  { name = "test1", payload = "..." },
  { name = "test2", payload = "..." }
]
```

### 2. Test Critical Paths

Focus on testing:
- IAM permissions
- Integration with other services
- Environment variable configuration
- Critical business logic

### 3. Keep Payloads Simple

Test invocations should be quick validation, not comprehensive testing:

```hcl
# Good - Quick validation
payload = jsonencode({ action = "health-check" })

# Bad - Complex, time-consuming operation
payload = jsonencode({ action = "process-all-data", timeout = 300 })
```

### 4. Environment-Specific Configuration

```hcl
test_invocations = var.environment == "production" ? [] : [
  { name = "dev-test", payload = "..." }
]
```

### 5. Use with CI/CD

Ideal for automated deployment pipelines:
- Validates deployment immediately
- Catches configuration errors early
- Provides quick feedback

## Comparison with Manual Testing

| Aspect | Module Invocations | Manual Testing |
|--------|-------------------|----------------|
| Timing | Automatic after deploy | Manual process |
| Consistency | Same tests every time | May vary |
| CI/CD Integration | Built-in | Requires scripting |
| Visibility | Terraform output | Separate logs |
| Response Files | Saved automatically | Must capture manually |

## Migration Guide

If you were using separate `null_resource` blocks, migrate to the module feature:

### Before

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"
  # ... config ...
}

resource "null_resource" "test" {
  provisioner "local-exec" {
    command = "aws lambda invoke ..."
  }
}
```

### After

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"
  # ... config ...

  test_invocations = [
    { name = "test", payload = "..." }
  ]
}
```

Benefits:
- Cleaner code
- Better encapsulation
- Automatic response file management
- Built-in output tracking
