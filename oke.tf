variable "config_file_profile" { type = string }
variable "home_region" { type = string }
variable "region" { type = string }
variable "tenancy_id" { type = string }
variable "compartment_id" { type = string }
variable "ssh_public_key_path" { type = string }

module "oke" {
  source = "github.com/oracle-terraform-modules/terraform-oci-oke.git?ref=5.x-dev&depth=1"

  # Provider
  providers           = { oci.home = oci.home }
  config_file_profile = var.config_file_profile
  home_region         = var.home_region
  region              = var.region
  tenancy_id          = var.tenancy_id
  compartment_id      = var.compartment_id
  ssh_public_key_path = var.ssh_public_key_path

  # Resource creation
  assign_dns           = true  # *true/false
  create_vcn           = true  # *true/false
  create_bastion       = true  # *true/false
  create_cluster       = true  # *true/false
  create_operator      = false # *true/false
  create_iam_resources = false # true/*false
  use_defined_tags     = true  # true/*false

  allow_worker_ssh_access     = true
  control_plane_allowed_cidrs = ["0.0.0.0/0"]

  # Worker pool defaults
  worker_image_id         = "ocid1.image.oc1.ap-osaka-1.aaaaaaaaykfhzcj5uowhvwrdewdmzqxwq7k53f3ac2wvlb2tpaiujgbcesla"
  worker_image_os         = "Oracle Linux" # Ignored when worker_image_type = "custom"
  worker_image_os_version = "8"            # Ignored when worker_image_type = "custom"
  worker_image_type       = "custom"       # Must be "custom" when using an image OCID
  worker_shape            = { shape = "VM.Standard.E4.Flex", ocpus = 2, memory = 16, boot_volume_size = 50 }

  worker_pools = {
    np0 = {
      description = "OKE-managed Node Pool", enabled = true,
      mode        = "node-pool", size = 1,
    }
    cn0 = {
      description = "Self-managed Cluster Network", enabled = true,
      mode        = "cluster-network", size = 2, shape = "BM.GPU.B4.8", placement_ads = [1],
      secondary_vnics = {
        # storage0 = { nic_index = 0 } # Pending instance config limits increase for hpc_limited_availability
        storage1 = { nic_index = 1 }
      }
    }
  }
}

terraform {
  required_providers {
    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 4.67.3"
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
