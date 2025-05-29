variable "prefix" {
  type    = string
  default = "ns-"
}

resource "kubernetes_namespace" "ns" {
  metadata {
    generate_name = var.prefix
  }
}

output "name" {
  value = kubernetes_namespace.ns.metadata[0].name
}

terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
