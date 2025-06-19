data "oci_core_images" "linux_image" {
  compartment_id   = var.compartment_id
  operating_system = "Canonical Ubuntu"
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24.04-aarch64-([\\.0-9-]+)$"]
    regex  = true
  }
}