resource "oci_containerengine_cluster" "cp" {
  compartment_id     = var.compartment_id
  kubernetes_version = local.kubernetes_version
  name               = "OKE-Cluster"
  vcn_id             = oci_core_vcn.main.id

  endpoint_config {
    subnet_id            = oci_core_subnet.endpoint.id
    is_public_ip_enabled = true
  }

  type = "BASIC_CLUSTER"
}

resource "oci_containerengine_node_pool" "worker" {
  cluster_id         = oci_containerengine_cluster.cp.id
  compartment_id     = var.compartment_id
  name               = "OKE-Node-Pool"
  node_shape         = "VM.Standard.E5.Flex"
  kubernetes_version = local.kubernetes_version

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.worker_image_id
  }

  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 16
  }

  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.worker.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
      subnet_id           = oci_core_subnet.worker.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[2].name
      subnet_id           = oci_core_subnet.worker.id
    }
    size = 2
  }
}