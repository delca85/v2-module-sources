# Lambda Module Changelog

## Latest Updates - Automatic Test Invocations Feature

### What's New

The Lambda module now supports **automatic test invocations** after deployment! You can configure the module to automatically invoke your Lambda function with test payloads to verify it's working correctly.

### New Variables

#### `test_invocations

- **Type**: `list(object({ name = string, payload = string }))`
- **Default**: `[]`
- **Description**: List of test invocations to run after Lambda deployment

**Example:**

```hcl
test_invocations = [
  {
    name    = "health-check"
    payload = jsonencode({ action = "ping" })
  },
  {
    name    = "validate-permissions"
    payload = jsonencode({ action = "test-s3" })
  }
]
```

#### `invoke_on_every_apply`

- **Type**: `bool`
- **Default**: `false`
- **Description**: Controls when invocations run
  - `true`: Run on every `terraform apply`
  - `false`: Only run when Lambda function changes

### New Resources

#### `null_resource.test_invocations`

- Automatically invokes Lambda with configured payloads
- Uses `for_each` to handle multiple invocations
- Saves responses to `/tmp/lambda-{name}-response.json`
- Displays results in Terraform output

### New Outputs

#### `test_invocations`

- Returns status and response file locations for all test invocations
- Empty object if no tests configured

**Example output:**

```json
{
  "list": {
    "id": "8934567890123456789",
    "response_file": "/tmp/lambda-list-response.json"
  }
}
```

### Usage Example

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-bucket"
  s3_key    = "function.zip"
  runtime   = "python3.12"
  handler   = "index.handler"

  # Automatic test invocations
  test_invocations = [
    {
      name    = "smoke-test"
      payload = jsonencode({ test = true })
    }
  ]

  invoke_on_every_apply = true
}
```

See [TEST-INVOCATIONS.md](TEST-INVOCATIONS.md) for complete documentation.

---

## Recent Updates - Optional IAM Policies Feature

### What Changed

The Lambda module now supports attaching optional additional IAM policies to the Lambda execution role. This makes the module more flexible and eliminates the need to create separate `aws_iam_role_policy` resources outside the module.

### New Variables

#### `additional_managed_policy_arns`

- **Type**: `list(string)`
- **Default**: `[]`
- **Description**: List of additional managed IAM policy ARNs to attach to the Lambda execution role
- **Use Case**: Attach AWS managed policies or your own customer-managed policies

**Example:**

```hcl
additional_managed_policy_arns = [
  "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
  "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
]
```

#### `additional_inline_policies`

- **Type**: `map(string)`
- **Default**: `{}`
- **Description**: Map of additional inline IAM policies. Key is the policy name, value is the policy document as JSON string
- **Use Case**: Define custom, function-specific policies inline

**Example:**

```hcl
additional_inline_policies = {
  s3_access = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::my-bucket/*"
    }]
  })
}
```

### New Resources

#### `aws_iam_role_policy_attachment.additional_managed_policies`

- Attaches each managed policy ARN from the `additional_managed_policy_arns` variable
- Uses `for_each` to iterate over the list
- Only created when `iam_role_arn` is `null` (module creates the role)

#### `aws_iam_role_policy.additional_inline_policies`

- Creates inline policies from the `additional_inline_policies` map
- Uses `for_each` to create one policy per map entry
- Only created when `iam_role_arn` is `null` (module creates the role)

### Migration Guide

#### Before (Old Pattern)

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-bucket"
  s3_key    = "function.zip"
  runtime   = "python3.12"
  handler   = "index.handler"
}

# Had to create policy separately
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "lambda-s3-access"
  role = module.my_lambda.role_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [...]
  })
}
```

#### After (New Pattern)

```hcl
module "my_lambda" {
  source = "./module-sources/lambda"

  s3_bucket = "my-bucket"
  s3_key    = "function.zip"
  runtime   = "python3.12"
  handler   = "index.handler"

  # Now included in the module
  additional_inline_policies = {
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [...]
    })
  }
}
```

### Benefits

1. **Cleaner Code**: IAM policies are defined alongside the Lambda configuration
2. **Better Encapsulation**: All Lambda-related resources in one module call
3. **Easier to Maintain**: No separate policy resources to track
4. **Flexible**: Support for both managed and inline policies
5. **Backward Compatible**: Existing configurations without these variables continue to work

### Important Notes

- **Existing Role Behavior**: When you provide `iam_role_arn`, the additional policies are NOT attached (you manage the role yourself)
- **Multiple Policies**: You can use both `additional_managed_policy_arns` and `additional_inline_policies` together
- **Policy Limits**: AWS limits apply (10 managed policies per role, 10,240 characters per inline policy)
- **Automatic Cleanup**: All policies are destroyed when the Lambda is destroyed

### File Changes

#### [variables.tf](variables.tf)

- Added `additional_managed_policy_arns` variable
- Added `additional_inline_policies` variable

#### [main.tf](main.tf)

- Added `aws_iam_role_policy_attachment.additional_managed_policies` resource
- Added `aws_iam_role_policy.additional_inline_policies` resource

### Testing

To verify the changes work correctly:

1. Apply a configuration with additional policies
2. Check the AWS Console to verify policies are attached
3. Test Lambda function with permissions
4. Destroy and verify policies are removed

### Example Configurations

See [USAGE-EXAMPLES.md](USAGE-EXAMPLES.md) for comprehensive examples including:

- Basic inline policy usage
- Managed policy attachment
- Combining both approaches
- Real-world scenarios
- Best practices
