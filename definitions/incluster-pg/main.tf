# Provider configuration
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Variables
variable "postgres_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "myapp"
}

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres"
}

variable "storage_size" {
  description = "Storage size for PostgreSQL"
  type        = string
  default     = "1Gi"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "default"
}

# Generate a random password
resource "random_password" "postgres_password" {
  length  = 16
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Secret
resource "kubernetes_secret" "postgres_secret" {
  metadata {
    name      = "postgres-secret"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    POSTGRES_PASSWORD = base64encode(random_password.postgres_password.result)
  }
}

# PersistentVolumeClaim (with explicit storage class)
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard" # Use Kind's default storage class explicitly

    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }

  wait_until_bound = false # Don't wait for binding during terraform apply
}

# Deployment
resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name              = "postgres"
          image             = "postgres:15"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 5432
          }

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_database
          }

          env {
            name  = "POSTGRES_USER"
            value = var.postgres_user
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            exec {
              command = ["/bin/sh", "-c", "pg_isready -U ${var.postgres_user} -d ${var.postgres_database}"]
            }
            initial_delay_seconds = 30
            period_seconds        = 5
          }

          liveness_probe {
            exec {
              command = ["/bin/sh", "-c", "pg_isready -U ${var.postgres_user} -d ${var.postgres_database}"]
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.postgres_secret
  ]
}

# Service
resource "kubernetes_service" "postgres_service" {
  metadata {
    name      = "postgres-service"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.postgres]
}

# Output
output "connection_string" {
  description = "PostgreSQL connection string for in-cluster access"
  value       = "postgresql://${var.postgres_user}:${urlencode(random_password.postgres_password.result)}@${kubernetes_service.postgres_service.metadata[0].name}:5432/${var.postgres_database}"
  sensitive   = true
}
