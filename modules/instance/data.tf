data "oci_core_images" "arm_image" {
  compartment_id   = var.compartment_id
  operating_system = "Canonical Ubuntu"
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24.04-Minimal-aarch64-([\\.0-9-]+)$"]
    regex  = true
  }
}

data "oci_core_images" "x86_image" {
  compartment_id   = var.compartment_id
  operating_system = "Canonical Ubuntu"
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24.04-Minimal-([\\.0-9-]+)$"]
    regex  = true
  }
}