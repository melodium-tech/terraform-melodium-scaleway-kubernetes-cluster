
variable "project_id" {
  type        = string
  description = "Scaleway project id (UUID)"
  default = "ed732865-8d9f-45a9-8025-79a82ba27651"
}

variable "region" {
  type        = string
  description = "Scaleway region"
  default     = "fr-par"
}

variable "zone" {
  type        = string
  description = "Scaleway zone"
  default     = "fr-par-2"
}

variable "cluster_name" {
  type        = string
  description = "Mélodium cluster name"
}

variable "cluster_description" {
  type        = string
  description = "Mélodium cluster name"
  default     = ""
}

variable "cluster_token" {
  type        = string
  description = "Mélodium cluster API token"
}

variable "cluster_work_pools" {
  type        = map(object({
    node_type   = string
    volume_size = number
    min_size    = number
    max_size    = number
  }))
  description = "Map of work pools"
  default = {
    "COPARM1-4C-16G" = {
      node_type = "COPARM1-4C-16G",
      volume_size = 50,
      min_size = 0
      max_size = 4
    },
    "DEV1-L" = {
      node_type = "DEV1-L",
      volume_size = 80,
      min_size = 1
      max_size = 14
    }
  }
}