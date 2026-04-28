#####################
##       VCN       ##
#####################

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = local.vcn_cidr
  display_name   = "main"
}

#####################
##     Subnets     ##
#####################

resource "oci_core_subnet" "endpoint" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = local.endpoint_subnet_cidr
  route_table_id    = oci_core_route_table.endpoint_rt.id
  security_list_ids = [oci_core_security_list.endpoint.id]
  display_name      = "endpoint"
}

resource "oci_core_subnet" "worker" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = local.worker_subnet_cidr
  route_table_id    = oci_core_route_table.worker_rt.id
  security_list_ids = [oci_core_security_list.worker.id]
  display_name      = "worker"
}

resource "oci_core_subnet" "lb" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = local.lb_subnet_cidr
  route_table_id    = oci_core_route_table.lb_rt.id
  security_list_ids = [oci_core_security_list.lb.id]
  display_name      = "lb"
}

#####################
##   Route Table   ##
#####################

resource "oci_core_route_table" "endpoint_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "endpoint_route_table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_route_table" "worker_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "worker_route_table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.ngw.id
  }

  route_rules {
    destination_type  = "SERVICE_CIDR_BLOCK"
    destination       = data.oci_core_services.all.services[0].cidr_block
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

resource "oci_core_route_table" "lb_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "lb_route_table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}


######################
## Internet Gateway ##
######################

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  enabled        = true
}

######################
## NAT Gateway ##
######################

resource "oci_core_nat_gateway" "ngw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
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

############################
## Security List Endpoint ##
############################

resource "oci_core_security_list" "endpoint" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "endpoint"

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

  # Allow nodes to communicate with OKE.
  egress_security_rules {
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = data.oci_core_services.all.services[0].cidr_block
    tcp_options {
      min = 443
      max = 443
    }
  }
}

##########################
## Security List Worker ##
##########################

resource "oci_core_security_list" "worker" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "worker"

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

  # Allows node to receive traffic from LB in port 30000 - 32767
  ingress_security_rules {
    protocol = "6"
    source   = local.lb_subnet_cidr
    tcp_options {
      min = 30000
      max = 32767
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

  # Allow LB to run health check in worker node
  ingress_security_rules {
    protocol = "6"
    source   = local.lb_subnet_cidr
    tcp_options {
      min = 10256
      max = 10256
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
    destination = local.worker_subnet_cidr
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

  # Allow nodes to communicate with OKE.
  egress_security_rules {
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = data.oci_core_services.all.services[0].cidr_block
    tcp_options {
      min = 443
      max = 443
    }
  }
}

######################
## Security List LB ##
######################
resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "lb"

  # Allow internet to access LB from port 80
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Allow LB to communicate with worker nodes at port 30000 - 32767
  egress_security_rules {
    protocol    = "6"
    destination = local.worker_subnet_cidr
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Allow LB to run health check in worker node
  egress_security_rules {
    protocol    = "6"
    destination = local.worker_subnet_cidr
    tcp_options {
      min = 10256
      max = 10256
    }
  }
}