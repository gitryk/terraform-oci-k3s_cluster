locals {
  flat_rules = flatten([
    for nsg_index, rules in var.nsg_rule : [
      for rule in rules : {
        nsg_index   = nsg_index
        min         = rule.min
        max         = rule.max
        type        = rule.type
        direction   = rule.direction
        target      = rule.target
        target_type = rule.target_type
        description = rule.description
      }
    ]
  ])
}

#IGW
resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = "${var.app_name}-igw"
}

#NAT
resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = "${var.app_name}-nat"
}

#라우팅 테이블 두개 생성
resource "oci_core_route_table" "route_map" {
  count = length(var.net_border)

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = "${var.app_name}-rt-${var.net_border[count.index]}"
  route_rules {
    network_entity_id = (
      var.net_border[count.index] == "pub"
      ? oci_core_internet_gateway.this.id
      : oci_core_nat_gateway.this.id
    )

    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
  }

  depends_on = [oci_core_nat_gateway.this, oci_core_nat_gateway.this]
}

#기본 보안 그룹(깡통)
resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = "${var.app_name}-seclist"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

}

#역할별 nsg 생성
resource "oci_core_network_security_group" "sec_group" {
  count          = length(var.net_secgroup)
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = "${var.app_name}-nsg-${var.net_secgroup[count.index]}"
}

#security rule 연결
resource "oci_core_network_security_group_security_rule" "sec_rule" {
  count     = length(local.flat_rules)
  protocol  = local.flat_rules[count.index].type
  direction = local.flat_rules[count.index].direction

  network_security_group_id = oci_core_network_security_group.sec_group[tonumber(local.flat_rules[count.index].nsg_index)].id

  source_type = local.flat_rules[count.index].direction == "INGRESS" ? local.flat_rules[count.index].target_type : null
  source = local.flat_rules[count.index].direction == "INGRESS" ? (
    local.flat_rules[count.index].target_type == "CIDR_BLOCK"
    ? local.flat_rules[count.index].target
    : oci_core_network_security_group.sec_group[tonumber(local.flat_rules[count.index].target)].id
  ) : null

  destination_type = local.flat_rules[count.index].direction == "EGRESS" ? local.flat_rules[count.index].target_type : null
  destination = local.flat_rules[count.index].direction == "EGRESS" ? (
    local.flat_rules[count.index].target_type == "CIDR_BLOCK"
    ? local.flat_rules[count.index].target
    : oci_core_network_security_group.sec_group[tonumber(local.flat_rules[count.index].target)].id
  ) : null

  dynamic "tcp_options" {
    for_each = local.flat_rules[count.index].type == 6 && local.flat_rules[count.index].direction == "INGRESS" ? [1] : []
    content {
      destination_port_range {
        min = local.flat_rules[count.index].min
        max = (local.flat_rules[count.index].max == null
          ? local.flat_rules[count.index].min
          : local.flat_rules[count.index].max)
      }
    }
  }

  dynamic "tcp_options" {
    for_each = local.flat_rules[count.index].type == 6 && local.flat_rules[count.index].direction == "EGRESS" ? [1] : []
    content {
      source_port_range {
        min = local.flat_rules[count.index].min
        max = (local.flat_rules[count.index].max == null
          ? local.flat_rules[count.index].min
          : local.flat_rules[count.index].max)
      }
    }
  }

  dynamic "udp_options" {
    for_each = local.flat_rules[count.index].type == 17 && local.flat_rules[count.index].direction == "INGRESS" ? [1] : []
    content {
      destination_port_range {
        min = local.flat_rules[count.index].min
        max = (local.flat_rules[count.index].max == null
          ? local.flat_rules[count.index].min
          : local.flat_rules[count.index].max)
      }
    }
  }

  dynamic "udp_options" {
    for_each = local.flat_rules[count.index].type == 17 && local.flat_rules[count.index].direction == "EGRESS" ? [1] : []
    content {
      source_port_range {
        min = local.flat_rules[count.index].min
        max = (local.flat_rules[count.index].max == null
          ? local.flat_rules[count.index].min
          : local.flat_rules[count.index].max)
      }
    }
  }

  description = local.flat_rules[count.index].description
  depends_on  = [oci_core_network_security_group.sec_group]
}

#서브넷 생성
resource "oci_core_subnet" "subnet_field" {
  count = length(var.net_border)

  cidr_block     = var.subnet_cidr[count.index]
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  #Optional
  display_name = "${var.app_name}-${var.net_border[count.index]}"
  prohibit_public_ip_on_vnic = (
    var.net_border[count.index] == "pub"
    ? false
    : true
  )

  route_table_id    = oci_core_route_table.route_map[count.index].id
  security_list_ids = [oci_core_security_list.this.id]

  depends_on = [oci_core_network_security_group.sec_group, oci_core_route_table.route_map]
}
