
resource "random_uuid" "terraform-control-common-key" {
}

provider "scaleway" {
  zone   = var.zone
  region = var.region
  project_id = var.project_id
}

resource "scaleway_vpc_private_network" "terraform-pn" {
  name        = format("%s-pn", var.cluster_name)
  region      = var.region
}

resource "scaleway_k8s_cluster" "terraform-cluster" {
  name    = format("%s-cluster", var.cluster_name)
  type    = "kapsule"
  version = "1.31.2"
  cni     = "cilium"
  private_network_id = scaleway_vpc_private_network.terraform-pn.id
  delete_additional_resources = true
}

resource "scaleway_instance_placement_group" "terraform-control-pool-availability-group" {
  name        = format("%s-control-pool-availability-group", var.cluster_name)
  policy_type = "max_availability"
  zone        = var.zone
}

resource "scaleway_instance_security_group" "terraform-security-group" {
  name = "kubernetes ${replace(scaleway_k8s_cluster.terraform-cluster.id, format("%s/", scaleway_k8s_cluster.terraform-cluster.region), "")}"
  description = format("Security group for %s cluster", var.cluster_name)
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  inbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "30000-32767"
    ip_range = "0.0.0.0/0"
  }
  inbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "30000-32767"
    ip_range = "::/0"
  }
}

resource "scaleway_k8s_pool" "terraform-control-pool" {
  depends_on  = [scaleway_instance_security_group.terraform-security-group]
  cluster_id  = scaleway_k8s_cluster.terraform-cluster.id
  name        = format("%s-control-pool", var.cluster_name)
  zone        = var.zone
  region      = var.region
  placement_group_id = scaleway_instance_placement_group.terraform-control-pool-availability-group.id
  tags        = ["noprefix=melodium-role=control"]
  node_type   = "COPARM1-2C-8G"
  size        = 1
  min_size    = 1
  max_size    = 3
  autoscaling = true
  autohealing = true
}

resource "scaleway_k8s_pool" "terraform-work-pool" {
  depends_on  = [scaleway_instance_security_group.terraform-security-group]

  for_each = var.cluster_work_pools

  cluster_id  = scaleway_k8s_cluster.terraform-cluster.id
  name        = format("%s-work-pool-%s", var.cluster_name, each.key)
  zone        = var.zone
  region      = var.region
  tags        = ["noprefix=melodium-role=work", format("noprefix=melodium-pool=%s", each.key)]
  container_runtime = "containerd"
  node_type   = each.value.node_type
  root_volume_size_in_gb = each.value.volume_size
  size        = 1
  min_size    = each.value.min_size
  max_size    = each.value.max_size
  autoscaling = true
  autohealing = true
}

resource "null_resource" "kubeconfig" {
  depends_on = [scaleway_k8s_pool.terraform-control-pool, scaleway_k8s_pool.terraform-work-pool]
  triggers = {
    host                   = scaleway_k8s_cluster.terraform-cluster.kubeconfig[0].host
    token                  = scaleway_k8s_cluster.terraform-cluster.kubeconfig[0].token
    cluster_ca_certificate = scaleway_k8s_cluster.terraform-cluster.kubeconfig[0].cluster_ca_certificate

    local_exec_api_uri = var.api_uri
    local_exec_cluster_token = var.cluster_token
    local_exec_cluster_id = uuidv5(var.project_id, var.cluster_name)
  }
  
  provisioner "local-exec" {
    environment = {
      URI = self.triggers.local_exec_api_uri
      TOKEN = self.triggers.local_exec_cluster_token
      ID = self.triggers.local_exec_cluster_id
    }
    command = "curl --silent --show-error -X DELETE -H \"Authorization: Bearer $TOKEN\" \"$URI/execution/cluster/$ID\" "
    when    = destroy
  }
}

provider "kubectl" {
  host                   = null_resource.kubeconfig.triggers.host
  token                  = null_resource.kubeconfig.triggers.token
  cluster_ca_certificate = base64decode(
    null_resource.kubeconfig.triggers.cluster_ca_certificate
  )
  
  load_config_file       = false
}

resource "tls_private_key" "rsa-key-melodium" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "kubectl_manifest" "k8s-melodium-namespace" {
  yaml_body = templatefile("${path.module}/k8s/00-melodium-namespace.yaml.tftpl", {})
}

resource "kubectl_manifest" "k8s-melodium-controller-cluster-role" {
  yaml_body = templatefile("${path.module}/k8s/01-melodium-controller-cluster-role.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-namespace ]
}

resource "kubectl_manifest" "k8s-melodium-controller-cluster-role-binding" {
  yaml_body = templatefile("${path.module}/k8s/02-melodium-controller-cluster-role-binding.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-controller-cluster-role ]
}

resource "kubectl_manifest" "k8s-melodium-controller-role" {
  yaml_body = templatefile("${path.module}/k8s/03-melodium-controller-role.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-controller-cluster-role-binding ]
}

resource "kubectl_manifest" "k8s-melodium-controller-role-binding" {
  yaml_body = templatefile("${path.module}/k8s/04-melodium-controller-role-binding.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-controller-role ]
}

resource "kubectl_manifest" "k8s-melodium-controller-service-account" {
  yaml_body = templatefile("${path.module}/k8s/05-melodium-controller-service-account.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-controller-role-binding ]
}

resource "kubectl_manifest" "k8s-melodium-controller-node-port" {
  yaml_body = templatefile("${path.module}/k8s/06-melodium-controller-node-port.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-controller-service-account ]
}

resource "kubectl_manifest" "k8s-melodium-pools-configmap" {
  yaml_body = templatefile("${path.module}/k8s/07-melodium-pools-configmap.yaml.tftpl", {
    pools = [
      for pool in scaleway_k8s_pool.terraform-work-pool: {
        id = replace(pool.id, format("%s/", pool.region), ""),
        node_provider = "scaleway",
        node_name = replace(upper(pool.node_type), "_", "-"),
        node_disk = floor(pool.root_volume_size_in_gb * 1000),
        max_nodes = pool.max_size
      }
    ]
  })
  depends_on = [ kubectl_manifest.k8s-melodium-controller-node-port ]
}

resource "kubectl_manifest" "k8s-melodium-images-pull-secret" {
  yaml_body = templatefile("${path.module}/k8s/08-melodium-images-pull-secret.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-pools-configmap ]
}

resource "kubectl_manifest" "k8s-melodium-controller-token" {
  yaml_body = templatefile("${path.module}/k8s/09-melodium-controller-token.yaml.tftpl",
  {
    token = var.cluster_token
  })
  depends_on = [ kubectl_manifest.k8s-melodium-images-pull-secret ]
}

resource "kubectl_manifest" "k8s-melodium-private-rsa-key" {
  yaml_body = templatefile("${path.module}/k8s/10-melodium-private-rsa-key.yaml.tftpl",
  {
    key_pem = tls_private_key.rsa-key-melodium.private_key_pem_pkcs8
  })
  depends_on = [ kubectl_manifest.k8s-melodium-controller-token ]
}

resource "kubectl_manifest" "k8s-melodium-cluster-certificate" {
  yaml_body = templatefile("${path.module}/k8s/11-melodium-cluster-certificate.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-private-rsa-key ]
}

resource "kubectl_manifest" "k8s-melodium-controller-deployment" {
  yaml_body = templatefile("${path.module}/k8s/12-melodium-controller-deployment.yaml.tftpl", {
    uuid = uuidv5(var.project_id, var.cluster_name)
    name = var.cluster_name
    description = var.cluster_description
    common_key = random_uuid.terraform-control-common-key.id
    api_uri = var.api_uri
    controller_image = "rg.${var.region}.scw.cloud/melodium/kube-controller:0.1-kube1.30"
    melodium_images_pull_source = "rg.${var.region}.scw.cloud/melodium"
  })
  wait_for_rollout = false
  depends_on = [ kubectl_manifest.k8s-melodium-cluster-certificate ]
}

resource "kubectl_manifest" "k8s-melodium-priorityclass-overprovisioning" {
  yaml_body = templatefile("${path.module}/k8s/13-melodium-priorityclass-overprovisioning.yaml.tftpl", {})
  depends_on = [ kubectl_manifest.k8s-melodium-images-pull-secret ]
}

resource "kubectl_manifest" "k8s-melodium-deployment-overprovisioning" {

  for_each = var.cluster_work_pools

  yaml_body = templatefile("${path.module}/k8s/14-melodium-deployment-overprovisioning.yaml.tftpl", {
    name = each.key
    storage_size = floor(max(each.value.volume_size / 2, 5))
  })
  wait_for_rollout = false
  depends_on = [ kubectl_manifest.k8s-melodium-priorityclass-overprovisioning ]
}
