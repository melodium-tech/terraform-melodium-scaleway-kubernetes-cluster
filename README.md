# Mélodium Scaleway Kubernetes Cluster

Terraform module managing all-in-one configuration to deploy Mélodium Cluster on Scaleway Kubernetes Kapsule.

## Authentication

To use this module, you need to have the Scaleway Terraform Provider able to reach Scaleway API. `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` environment variables must be set up.  
Refer to the [Authentication](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs#authentication) section of Scaleway Terraform Provider to proceed.

You also need a Mélodium Cluster Token, that can be generated on Mélodium account.  
Refer to [Mélodium: Deploy Cluster on Scaleway](https://ci.melodium.tech/en/docs/clusters/scaleway) for more information.

## Usage

```terraform

module "scaleway-kubernetes-cluster" {
  source  = "melodium-tech/scaleway-kubernetes-cluster/melodium"
  version = "0.0.3"
  
  // Project UUID (available in Scaleway Console near project name)
  project_id = "<YOUR PROJECT ID>" 
  
  // Cluster name (must be unique across your organization)
  cluster_name = "my-cluster-01"
  cluster_description = "Cluster test on Scaleway"

  // Cluster token to connect with Mélodium API
  cluster_token = "<YOUR CLUSTER TOKEN>"

  // Scaleway Region
  region = "fr-par"
  // Scaleway Zone
  zone = "fr-par-2"

  // Pools to include in cluster
  cluster_work_pools = {
    "arm-4C-16G" = {
      // Scaleway Node Type
      node_type = "COPARM1-4C-16G"
      // Disk in GB
      volume_size = 80
      // Minimal number of machines present at any time in this pool
      min_size = 0
      // Absolute maximum number of machines in this pool
      max_size = 4 
    },
    "amd-4C-16G" = {
      node_type = "GP1-XS"
      volume_size = 80
      min_size = 0
      max_size = 4
    }
  }

}

```

## More

- [Mélodium Technology](https://melodium.tech/)
- [Deploy Cluster on Scaleway](https://ci.melodium.tech/en/docs/clusters/scaleway)
