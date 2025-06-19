variable "compartment_id" { type = string }
variable "vcn_id" { type = string }
variable "app_name" { type = string }

variable "net_border" { type = list(string) }
variable "net_secgroup" { type = list(string) }
variable "nsg_rule" { type = map(list(object({ min = number, max = number, type = number, direction = string, target = string, target_type = string, description = string }))) }

variable "subnet_cidr" { type = list(string) }