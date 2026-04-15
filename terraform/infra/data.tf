data "oci_identity_availability_domains" "ads" {
    compartment_id = var.compartment_id
}

data "oci_core_images" "oke_node_image" {
    compartment_id = var.compartment_id
    operating_system = "Oracle Linux"
    operating_system_version = "8"
    shape = "VM.Standard.A1.Flex"
    sort_by = "TIMECREATED"
    sort_order = "DESC"
}

data "oci_containerengine_cluster_option" "oke" {
    cluster_option_id = "all"
}