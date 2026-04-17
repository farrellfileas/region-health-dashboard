locals {
  kubernetes_version = "v1.32.1"

  worker_image_id = [
    for s in data.oci_containerengine_node_pool_option.worker.sources :
    s.image_id
    if !can(regex("aarch64|GPU", s.source_name)) && can(regex("OKE-1\\.32\\.1", s.source_name))
  ][0]

  endpoint_subnet_cidr = "10.0.0.0/24"
  worker_subnet_cidr   = "10.0.1.0/24"
  vcn_cidr             = "10.0.0.0/16"

}