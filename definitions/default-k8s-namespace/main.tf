variable "prefix" {
  type    = string
  default = "ns-"
}

variable "project" {
  type    = string
  default = "test-project"
}

resource "kubernetes_namespace" "ns" {
  metadata {
    generate_name = var.prefix
  }
}

output "name" {
  value = kubernetes_namespace.ns.metadata[0].name
}

output "humanitec_metadata" {
  value = var.project
}

terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
