output "nsg_id" {
  value = [for sg in oci_core_network_security_group.sec_group : sg.id]
}

output "subnet_id" {
  value = [for sn in oci_core_subnet.subnet_field : sn.id]
}