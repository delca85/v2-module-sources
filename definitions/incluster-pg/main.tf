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

# Generate a random password (URL-safe characters only)
resource "random_password" "postgres_password" {
  length  = 16
  special = false # Avoid special characters that need URL encoding
  upper   = true
  lower   = true
  numeric = true
}

# ConfigMap
resource "kubernetes_config_map" "postgres_config" {
  metadata {
    name      = "postgres-config"
    namespace = var.namespace
  }

  data = {
    POSTGRES_DB   = var.postgres_database
    POSTGRES_USER = var.postgres_user
  }
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

# PersistentVolumeClaim (using Kind's default storage class)
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }
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
            name = "POSTGRES_DB"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.postgres_config.metadata[0].name
                key  = "POSTGRES_DB"
              }
            }
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.postgres_config.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
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
              command = ["/bin/sh", "-c", "pg_isready -U postgres -d myapp"]
            }
            initial_delay_seconds = 30
            period_seconds        = 5
          }

          liveness_probe {
            exec {
              command = ["/bin/sh", "-c", "pg_isready -U postgres -d myapp"]
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
    kubernetes_config_map.postgres_config,
    kubernetes_secret.postgres_secret,
    kubernetes_persistent_volume_claim.postgres_pvc
  ]
}

# ClusterIP Service (required for internal access)
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

# Outputs

output "connection_string" {
  description = "PostgreSQL connection string for in-cluster access (URL-encoded)"
  value       = "postgresql://${var.postgres_user}:${urlencode(random_password.postgres_password.result)}@${kubernetes_service.postgres_service.metadata[0].name}.${var.namespace}.svc.cluster.local:5432/${var.postgres_database}"
  sensitive   = true
}
