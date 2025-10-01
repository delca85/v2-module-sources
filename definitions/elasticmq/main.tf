terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

variable "namespace" {
  description = "Kubernetes namespace to deploy ElasticMQ"
  type        = string
  default     = "default"
}

variable "name" {
  description = "Name for the ElasticMQ deployment"
  type        = string
  default     = "elasticmq"
}

variable "image" {
  description = "ElasticMQ Docker image"
  type        = string
  default     = "softwaremill/elasticmq-native:latest"
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 1
}

variable "port" {
  description = "Port for ElasticMQ service"
  type        = number
  default     = 9324
}

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
  default     = "default"
}

variable "queue_visibility_timeout" {
  description = "Default visibility timeout for messages"
  type        = string
  default     = "10 seconds"
}

variable "queue_delay" {
  description = "Delay before messages become available"
  type        = string
  default     = "5 seconds"
}

variable "queue_receive_wait" {
  description = "Long polling wait time"
  type        = string
  default     = "0 seconds"
}

variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}

locals {
  default_labels = {
    app     = var.name
    managed = "terraform"
  }
  all_labels = merge(local.default_labels, var.labels)
}

resource "kubernetes_config_map" "elasticmq" {
  metadata {
    name      = "${var.name}-config"
    namespace = var.namespace
    labels    = local.all_labels
  }

  data = {
    "elasticmq.conf" = <<-EOT
      include classpath("application.conf")
      node-address {
        protocol = http
        host = "*"
        port = ${var.port}
        context-path = ""
      }
      rest-sqs {
        enabled = true
        bind-port = ${var.port}
        bind-hostname = "0.0.0.0"
        sqs-limits = strict
      }
      queues {
        ${var.queue_name} {
          defaultVisibilityTimeout = ${var.queue_visibility_timeout}
          delay = ${var.queue_delay}
          receiveMessageWait = ${var.queue_receive_wait}
        }
      }
    EOT
  }
}

resource "kubernetes_deployment" "elasticmq" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.all_labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = var.name
      }
    }

    template {
      metadata {
        labels = local.all_labels
      }

      spec {
        container {
          name  = var.name
          image = var.image

          port {
            container_port = var.port
            name           = "http"
          }

          volume_mount {
            name       = "config"
            mount_path = "/opt/elasticmq.conf"
            sub_path   = "elasticmq.conf"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = var.port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = var.port
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.elasticmq.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "elasticmq" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.all_labels
  }

  spec {
    selector = {
      app = var.name
    }

    port {
      name        = "http"
      port        = var.port
      target_port = var.port
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

output "service_name" {
  description = "Name of the ElasticMQ service"
  value       = kubernetes_service.elasticmq.metadata[0].name
}

output "service_endpoint" {
  description = "Full endpoint URL for ElasticMQ"
  value       = "http://${kubernetes_service.elasticmq.metadata[0].name}.${var.namespace}.svc.cluster.local:${var.port}"
}

output "name" {
  description = "Name of the configured queue"
  value       = var.queue_name
}

output "url" {
  description = "Full queue URL"
  value       = "http://${kubernetes_service.elasticmq.metadata[0].name}.${var.namespace}.svc.cluster.local:${var.port}/000000000000/${var.queue_name}"
}

output "port" {
  description = "Service port"
  value       = var.port
}
