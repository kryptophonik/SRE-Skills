# Lab root module (v2, the change under review) for docs/examples/06-terraform-plan-and-drift.md.
# Copy it over the bootstrapped v1 in your lab dir. Local providers only: no cloud.
terraform {
  required_version = ">= 1.16"
  required_providers {
    local  = { source = "hashicorp/local", version = "~> 2.5" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}

variable "env" {
  type    = string
  default = "lab"
}

resource "random_pet" "cluster_name" {
  length = 3   # ops asked for longer names
}

resource "random_password" "db" {
  length  = 20
  special = false
}

resource "local_file" "app_config" {
  filename        = "${path.module}/out/app.conf"
  file_permission = "0600"
  content         = "env=${var.env}\ncluster=${random_pet.cluster_name.id}\nreplicas=3\n"
}

resource "local_sensitive_file" "db_dsn" {
  filename = "${path.module}/out/db.dsn"
  content  = "postgres://app:${random_password.db.result}@db.${var.env}.internal:5432/shop"
}

output "cluster_name" {
  value = random_pet.cluster_name.id
}
