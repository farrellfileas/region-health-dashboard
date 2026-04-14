resource "oci_core_vcn" "main" {
    compartment_id = local.compartment_id
    cidr_block     = "10.0.0.0/16"
}

resource "oci_core_subnet" "endpoint" {
    compartment_id = local.compartment_id
    vcn_id         = oci_core_vcn.main.id
    cidr_block     = "10.0.0.0/24"
    route_table_id = oci_core_route_table.rt.id
    security_list_ids = [oci_core_security_list.endpoint.id]
}

resource "oci_core_subnet" "worker" {
    compartment_id = local.compartment_id
    vcn_id         = oci_core_vcn.main.id
    cidr_block     = "10.0.1.0/24"
    route_table_id = oci_core_route_table.rt.id
    security_list_ids = [oci_core_security_list.worker.id]
}

resource "oci_core_internet_gateway" "igw" {
    compartment_id = local.compartment_id
    vcn_id         = oci_core_vcn.main.id
    is_enabled     = true
}

resource "oci_core_route_table" "rt" {
    compartment_id = local.compartment_id
    vcn_id         = oci_core_vcn.main.id

    route_rules {
        destination       = "0.0.0.0/0"
        network_entity_id = oci_core_internet_gateway.igw.id
    }
}

resource "oci_core_security_list" "endpoint" {
    compartment_id = local.compartment_id
    vcn_id         = oci_core_vcn.main.id
    name           = "OKE-Security-List"

    # Allows Internet access to Kubernetes API server
    ingress_security_rules {
        protocol = "6" # TCP
        source   = "0.0.0.0/0"
        tcp_options {
            destination_port_range {
                max = 6443 # Kubernetes API server port, for external kubectl access
                min = 6443
            }
        }
    }

    # Allows Kubernetes API server to communicate with worker nodes
    egress_security_rules {
        protocol = "6"
        destination = "10.0.1.0/24"
        tcp_options {
            destination_port_range {
                max = 10250 # Kubelet API port in worker nodes
                min = 10250
            }
        }
    }
}

resource "oci_core_security_list" "worker" {
    compartment_id = local.compartment_id
    vcn_id         = oci_core_vcn.main.id
    name           = "OKE-Worker-Security-List"

     # Allows Kubernetes API server to communicate with worker nodes 
    ingress_security_rules {
        protocol = "6" # TCP
        source   = "10.0.0.0/24"
        tcp_options {
            destination_port_range {
                max = 10250 # Kubelet API port
                min = 10250
            }
        }
    }
    
    # Allows inbound from other workers
    ingress_security_rules {
        protocol = "all"
        source   = "10.0.1.0/24"
    }

    # Allows SSH access to worker nodes from OKE CP to bootstrap new nodes
    ingress_security_rules {
        protocol = "6"
        source   = "0.0.0.0/0" # Allow from anywhere for testing; restrict in production
        tcp_options {
            destination_port_range {
                max = 22 # SSH port
                min = 22
            }
        }
    }

    # Allow outbound to other workers
    egress_security_rules {
        protocol = "all"
        destination = "10.0.1.0/24"
    }

    # Allows worker nodes to access the Internet for updates and pulling container images
    egress_security_rules {
        protocol = "6"
        destination = "0.0.0.0/0"
        # No port restrictions for outbound.
    }

    # Allows worker nodes to communicate with Kubernetes API server
    egress_security_rules {
        protocol = "6"
        destination = "10.0.0.0/24"
        tcp_options {
            destination_port_range {
                max = 6443
                min = 6443
            }
        }
    }
}