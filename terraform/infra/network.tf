#####################
##       VCN       ##
#####################

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = local.vcn_cidr
  display_name   = "OKE-VCN"
}

#####################
##     Subnets     ##
#####################

resource "oci_core_subnet" "endpoint" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = local.endpoint_subnet_cidr
  route_table_id    = oci_core_route_table.rt.id
  security_list_ids = [oci_core_security_list.endpoint.id]
  display_name      = "OKE-Endpoint-Subnet"
}

resource "oci_core_subnet" "worker" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = local.worker_subnet_cidr
  route_table_id    = oci_core_route_table.rt.id
  security_list_ids = [oci_core_security_list.worker.id]
  display_name      = "OKE-Worker-Subnet"
}

#####################
## Internet Gateway ##
#####################

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  enabled        = true
}

#####################
##   Route Table   ##
#####################

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "OKE-Route-Table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }

  route_rules {
    destination_type  = "SERVICE_CIDR_BLOCK"
    destination       = data.oci_core_services.all.services[0].cidr_block
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

#####################
## Service Gateway ##
#####################

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

###########################
## Security List Endpoint ##
###########################

resource "oci_core_security_list" "endpoint" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "OKE-Security-List"

  # Allows Internet access to Kubernetes API server
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      max = 6443 # Kubernetes API server port, for external kubectl access
      min = 6443
    }
  }

  # Kubernetes worker to Kubernetes API endpoint communication.
  ingress_security_rules {
    protocol = "6"
    source   = local.worker_subnet_cidr
    tcp_options {
      max = 12250
      min = 12250
    }
  }

  # Kubernetes worker to Kubernetes API endpoint communication.
  ingress_security_rules {
    protocol = "6"
    source   = local.worker_subnet_cidr
    tcp_options {
      max = 6443
      min = 6443
    }
  }

  # Path Discovery.
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = local.worker_subnet_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }

  # All traffic to worker nodes (when using flannel for pod networking).
  egress_security_rules {
    protocol    = "6"
    destination = local.worker_subnet_cidr
  }

  # Path Discovery.
  egress_security_rules {
    protocol    = "1" # ICMP
    destination = local.worker_subnet_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }
}

##########################
## Security List Worker  ##
##########################

resource "oci_core_security_list" "worker" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "OKE-Worker-Security-List"

  # Allows communication from (or to) worker nodes.
  ingress_security_rules {
    protocol = "all"
    source   = local.worker_subnet_cidr
  }

  # Allows SSH access to worker nodes from OKE CP to bootstrap new nodes
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0" # Allow from anywhere for testing; restrict in production
    tcp_options {
      max = 22 # SSH port
      min = 22
    }
  }

  # Allow Kubernetes API endpoint to communicate with worker nodes.
  ingress_security_rules {
    protocol = "6"
    source   = local.endpoint_subnet_cidr
  }

  # Path Discovery.
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }


  # Allows worker nodes to access the Internet for updates and pulling container images
  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
    # No port restrictions for outbound.
  }

  # Allows communication from (or to) worker nodes.
  egress_security_rules {
    protocol    = "all"
    destination = local.endpoint_subnet_cidr
  }

  # Kubernetes worker to Kubernetes API endpoint communication.
  egress_security_rules {
    protocol    = "6"
    destination = local.endpoint_subnet_cidr
    tcp_options {
      max = 12250
      min = 12250
    }
  }

  # Kubernetes worker to Kubernetes API endpoint communication.
  egress_security_rules {
    protocol    = "6"
    destination = local.endpoint_subnet_cidr
    tcp_options {
      max = 6443
      min = 6443
    }
  }

  # Path Discovery.
  egress_security_rules {
    protocol    = "1" # ICMP
    destination = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }
}
