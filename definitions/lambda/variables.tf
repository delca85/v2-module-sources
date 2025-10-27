variable "s3_bucket" {
  description = "The S3 bucket name where the Lambda deployment package (zip) is stored"
  type        = string
}

variable "s3_key" {
  description = "The S3 object key (path) for the Lambda deployment package"
  type        = string
}

variable "handler" {
  description = "The function entrypoint in your code (e.g., 'index.handler' for Node.js)"
  type        = string
}

variable "runtime" {
  description = "The Lambda runtime identifier (e.g., 'python3.12', 'nodejs20.x', 'java21')"
  type        = string
}

variable "iam_role_arn" {
  description = "Optional IAM role ARN to use for the Lambda function. If not provided, a new role will be created"
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region where the Lambda function will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "architectures" {
  description = "Instruction set architecture for the Lambda function. Valid values: ['x86_64'] or ['arm64']"
  type        = list(string)
  default     = ["x86_64"]
}

variable "timeout_in_seconds" {
  description = "The amount of time the Lambda function has to run in seconds"
  type        = number
  default     = 300
}

variable "additional_tags" {
  description = "Additional tags to apply to the Lambda function"
  type        = map(string)
  default     = {}
}

variable "environment_variables" {
  description = "Environment variables to pass to the Lambda function"
  type        = map(string)
  default     = {}
}

variable "memory_size" {
  description = "Amount of memory in MB that your Lambda function can use at runtime. Valid value between 128 MB to 10,240 MB"
  type        = number
  default     = 128
}

variable "name_prefix" {
  description = "Prefix for the Lambda function name"
  type        = string
  default     = "humanitec-platform-orchestrator-"
}

# variable "service" {
#   description = "Service configuration to determine if Function URL should be created"
#   type = object({
#     ports = optional(map(object({
#       port     = number
#       protocol = optional(string)
#     })), {})
#   })
#   default = {
#     ports = {}
#   }
# }

variable "metadata" {
  description = "Metadata for the Lambda function including annotations"
  type = object({
    annotations = optional(map(string), {})
  })
  default = {
    annotations = {}
  }
}

variable "additional_managed_policy_arns" {
  description = "List of additional managed IAM policy ARNs to attach to the Lambda execution role"
  type        = list(string)
  default     = []
}

variable "additional_inline_policies" {
  description = "Map of additional inline IAM policies to attach to the Lambda execution role. Key is the policy name, value is the policy document as JSON string"
  type        = map(string)
  default     = {}
}

variable "enable_function_url" {
  description = "If true, creates an HTTPS endpoint (Function URL) for the Lambda. Allows HTTP/HTTPS invocation."
  type        = bool
  default     = false
}

variable "function_url_auth_type" {
  description = "Authorization type for the Function URL. 'NONE' = public access, 'AWS_IAM' = requires AWS credentials."
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth_type)
    error_message = "function_url_auth_type must be either 'NONE' or 'AWS_IAM'."
  }
}

variable "function_url_cors" {
  description = "CORS configuration for the Function URL. Only applies if enable_function_url is true."
  type = object({
    allow_credentials = optional(bool, false)
    allow_origins     = optional(list(string), ["*"])
    allow_methods     = optional(list(string), ["*"])
    allow_headers     = optional(list(string), [])
    expose_headers    = optional(list(string), [])
    max_age           = optional(number, 0)
  })
  default = null
}
