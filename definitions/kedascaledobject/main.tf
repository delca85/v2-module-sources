# Provider configuration
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Variables
variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "default"
}

variable "prefix" {
  description = "Kubernetes namespace"
  type        = string
}

variable "polling_interval" {
  description = "Polling interval in seconds"
  type        = number
  default     = 30
}

variable "min_replica_count" {
  description = "Minimum number of replicas"
  type        = number
  default     = 1
}

variable "max_replica_count" {
  description = "Maximum number of replicas"
  type        = number
  default     = 10
}


variable "triggers" {
  description = "List of KEDA triggers"
  type = list(object({
    type = string
    # SQS-specific fields
    queueURL              = optional(string)
    queueLength           = optional(number)
    awsRegion             = optional(string)
    activationQueueLength = optional(number)
    scaleOnInFlight       = optional(bool)
    scaleOnDelayed        = optional(bool)
    # CPU/Memory-specific fields
    metricType = optional(string)
    value      = optional(string)
  }))

  validation {
    condition = alltrue([
      for trigger in var.triggers :
      contains(["aws-sqs-queue", "cpu", "memory"], trigger.type)
    ])
    error_message = "Trigger type must be one of: aws-sqs-queue, cpu, memory"
  }
}



resource "kubernetes_manifest" "keda_trigger_auth" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"

    metadata = {
      name      = "${var.prefix}-keda-trigger-auth"
      namespace = var.namespace
    }

    spec = {
      podIdentity = {
        provider      = "aws"
        identityOwner = "keda"
      }
    }
  }
}

resource "kubernetes_manifest" "keda_scaled_object" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"

    metadata = {
      name      = "${var.prefix}-scaled-object"
      namespace = var.namespace
      annotations = {
        "scaledobject.keda.sh/transfer-hpa-ownership" = "false"
        "validations.keda.sh/hpa-ownership"           = "false"
        "autoscaling.keda.sh/paused"                  = "false"
      }
    }

    spec = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = split(".", var.prefix)[1]
      }

      pollingInterval  = var.polling_interval
      cooldownPeriod   = 300
      idleReplicaCount = 0
      minReplicaCount  = var.min_replica_count
      maxReplicaCount  = var.max_replica_count

      triggers = [
        for trigger in var.triggers : merge(
          {
            type = trigger.type
          },
          # AWS SQS Queue trigger
          trigger.type == "aws-sqs-queue" ? {
            authenticationRef = {
              name = "${var.prefix}-keda-trigger-auth"
            }
            metadata = {
              queueURL      = trigger.queueURL
              queueLength   = tostring(trigger.queueLength)
              awsRegion     = "elasticmq"
              identityOwner = "pod"
            }
          } : {},
          # CPU trigger
          trigger.type == "cpu" ? {
            metricType = trigger.metricType
            metadata = {
              value = tostring(trigger.value)
            }
          } : {},
          # Memory trigger
          trigger.type == "memory" ? {
            metricType = trigger.metricType
            metadata = {
              value = tostring(trigger.value)
            }
          } : {}
        )
      ]
    }
  }
}

# Example usage:
# triggers = [
#   {
#     type        = "aws-sqs-queue"
#     queueURL    = "https://sqs.us-east-1.amazonaws.com/123456789/my-queue"
#     queueLength = 5
#     awsRegion   = "us-east-1"
#   },
#   {
#     type       = "cpu"
#     metricType = "Utilization"
#     value      = "80"
#   },
#   {
#     type       = "memory"
#     metricType = "Utilization"
#     value      = "70"
#   }
# ]
