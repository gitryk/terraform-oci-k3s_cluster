locals {
  private_key = base64encode(file("./keys/instance/private.key"))
}

resource "oci_core_instance" "tower" {
  availability_domain  = var.region_ad
  compartment_id       = var.compartment_id
  display_name         = "${var.app_name}-vm-tower"
  fault_domain         = "FAULT-DOMAIN-1"
  preserve_boot_volume = "false"

  shape = "VM.Standard.A1.Flex" #ARM A1
  shape_config {
    ocpus         = 1 #core
    memory_in_gbs = 6 #ram
  }

  source_details {
    source_id               = data.oci_core_images.linux_image.images[0].id
    source_type             = "image"
    boot_volume_size_in_gbs = 50 #boot disk 크기
  }

  metadata = {
    ssh_authorized_keys = file("./keys/instance/public.key")
    user_data = base64encode(
      templatefile("./script/tower.sh", {
        tail_key    = var.tail_key
        tail_subnet = var.subnet_cidr[1]
        app_name    = var.app_name
        private_key = local.private_key
      })
    )
  }

  agent_config {
    are_all_plugins_disabled = true
    is_management_disabled   = true
    is_monitoring_disabled   = true
  }

  create_vnic_details {
    assign_public_ip          = false #공인 ip 허용여부
    assign_ipv6ip             = false
    assign_private_dns_record = false
    #display_name              = "${var.app_name}-vnic-tower"
    nsg_ids    = [var.nsg_id[2]] #0:lb, 1:worker, 2:tower
    private_ip = var.instance_ip[3]
    subnet_id  = var.subnet_id[1] #0:public, 1:private
  }

  lifecycle { ignore_changes = [defined_tags, freeform_tags, source_details] }
}

resource "oci_core_instance" "worker" {
  count = length(var.instance_ip) - 1

  availability_domain  = var.region_ad
  compartment_id       = var.compartment_id
  display_name         = "${var.app_name}-vm-worker-${count.index}"
  fault_domain         = "FAULT-DOMAIN-${count.index + 1}"
  preserve_boot_volume = "false"

  shape = "VM.Standard.A1.Flex" #ARM A1
  shape_config {
    ocpus         = 1 #core
    memory_in_gbs = 6 #ram
  }

  source_details {
    source_id               = data.oci_core_images.linux_image.images[0].id
    source_type             = "image"
    boot_volume_size_in_gbs = 50 #boot disk 크기
  }

  metadata = {
    ssh_authorized_keys = file("./keys/instance/public.key")
    user_data = base64encode(
      templatefile("./script/worker.sh", {
        node_index       = count.index
        master_ip        = var.instance_ip[0]
        bastion_ip       = var.instance_ip[3]
        k3s_token        = var.k3s_token
        node_name        = "${var.app_name}-worker-${count.index}"
        domain           = var.domain
        lb_ip            = var.lb_ip
        subnet_cidr_pub  = var.subnet_cidr[0]
        subnet_cidr_priv = var.subnet_cidr[1]
      })
    )
  }

  agent_config {
    are_all_plugins_disabled = true
    is_management_disabled   = true
    is_monitoring_disabled   = true
  }

  create_vnic_details {
    assign_public_ip          = false #공인 ip 허용여부
    assign_ipv6ip             = false
    assign_private_dns_record = false
    #display_name              = "${var.app_name}-vnic-tower"
    nsg_ids    = [var.nsg_id[1]] #0:lb, 1:worker, 2:tower
    private_ip = var.instance_ip[count.index]
    subnet_id  = var.subnet_id[1] #0:public, 1:private
  }

  lifecycle { ignore_changes = [defined_tags, freeform_tags, source_details] }
}
