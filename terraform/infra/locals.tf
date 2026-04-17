locals {
  kubernetes_version = "v1.32.1"

  worker_image_id = [
    for s in data.oci_containerengine_node_pool_option.worker.sources :
    s.image_id
    if !can(regex("aarch64|GPU", s.source_name)) && can(regex("OKE-1\\.32\\.1", s.source_name))
  ][0]
}