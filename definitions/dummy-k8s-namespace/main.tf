variable "prefix" {
  type    = string
  default = "ns-"
}

variable "project" {
  type    = string
  default = "test-project"
}

resource "random_string" "dummy" {
  length  = 8
  upper   = false
  special = false
}
output "name" {
  value = "${var.prefix}-${random_string.dummy.id}"
}

output "humanitec_metadata" {
  value = {
    "project" = var.project
  }
}
