variable "config_file_profile" { type = string }
variable "home_region" { type = string }
variable "region" { type = string }
variable "tenancy_id" { type = string }
variable "compartment_id" { type = string }
variable "ssh_public_key_path" { type = string }
variable "ssh_private_key_path" { type = string }

module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.0.0-beta.6"

  # Provider
  providers           = { oci.home = oci.home }
  config_file_profile = var.config_file_profile
  home_region         = var.home_region
  region              = var.region
  tenancy_id          = var.tenancy_id
  compartment_id      = var.compartment_id
  ssh_public_key_path = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path
  
  kubernetes_version = "v1.26.2"
  cluster_type = "enhanced"
  cluster_name         = "oguz-test-cluster"
  bastion_allowed_cidrs = ["0.0.0.0/0"]
  allow_worker_ssh_access     = true
  control_plane_allowed_cidrs = ["0.0.0.0/0"]

  sriov_cni_plugin_install       = true
  sriov_cni_plugin_namespace     = "kube-system"
  
  rdma_cni_plugin_install       = true
  rdma_cni_plugin_namespace     = "kube-system"
  
  # Resource creation
  assign_dns           = false
  create_vcn           = true
  create_bastion       = true
  create_cluster       = true
  create_operator      = true
  create_iam_resources = false
  use_defined_tags     = false
  

  # Use the first /17 block in each region for OKE resources
  subnets = {
    bastion  = { create = "always", newbits = 11 }
    operator = { create = "always", newbits = 6 }
    cp       = { create = "always", newbits = 6 }
    workers  = { create = "always", newbits = 3 }
    pods     = { create = "always", newbits = 3 }
    int_lb   = { create = "always", newbits = 6 }
    pub_lb   = { create = "always", newbits = 6 }
  }

  nsgs = {
    bastion  = { create = "always" }
    operator = { create = "always" }
    cp       = { create = "always" }
    workers  = { create = "always" }
    pods     = { create = "always" }
    int_lb   = { create = "always" }
    pub_lb   = { create = "always" }
  }

  
  
  worker_pools = {
    system = {
      description = "CPU pool", enabled = true
      mode        = "node-pool", image_type = "custom", image_id = "ocid1.image.oc1.ap-osaka-1.aaaaaaaa7enhakmf4dkai4pnof7bzd3c3x4qua7t6fk4uk3fyeywhmvbl6wa", boot_volume_size = 256, shape = "VM.Standard.E4.Flex", ocpus = 16, memory = 128, size = 1,
    }
    a100-rdma = {
      description = "GPU pool", enabled = true, disable_default_cloud_init=true,
      mode        = "cluster-network", image_type = "custom", image_id = "ocid1.image.oc1.ap-osaka-1.aaaaaaaay3cckx4bgnn6xrmizj5f73f4xivbdlio3p3g4mrs4twtev7qgrvq", size = 2, shape = "BM.GPU.B4.8", boot_volume_size = 256, placement_ads = [1],
      node_labels = { "oci.oraclecloud.com/disable-gpu-device-plugin" : "true" },
      cloud_init = [{ content = "./cloud-init/gpu-cloud-init-ol.sh" }],
    }       
  }
}
terraform {
  required_providers {
    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 5.4.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "oci" {
  config_file_profile = var.config_file_profile
  region              = var.region
  tenancy_ocid        = var.tenancy_id
}

provider "oci" {
  alias               = "home"
  config_file_profile = var.config_file_profile
  region              = var.home_region
  tenancy_ocid        = var.tenancy_id
}