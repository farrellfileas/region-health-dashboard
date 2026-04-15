output "cluster_id" {
  description = "The ID of the OKE cluster"
  value       = oci_containerengine_cluster.cp.id
}

output "endpoint" {
  description = "The endpoint of the OKE cluster"
  value       = oci_containerengine_cluster.cp.endpoints[0].public_endpoint
  sensitive   = true
}

output "node_pool_id" {
  description = "The ID of the node pool"
  value       = oci_containerengine_node_pool.worker.id
}

# All outputs needed for kubectl configuration
# oci ce cluster create-kubeconfig --cluster-id <cluster-id> --region <region>