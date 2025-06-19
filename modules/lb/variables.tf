variable "compartment_id" { type = string }
variable "vcn_id" { type = string }
variable "app_name" { type = string }
variable "subnet_id" { type = list(string) }
variable "nsg_id" { type = list(string) }
variable "instance_ip" { type = list(string) }