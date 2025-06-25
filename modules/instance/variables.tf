variable "compartment_id" { type = string }
variable "vcn_id" { type = string }
variable "region_ad" { type = string }
variable "app_name" { type = string }

variable "nsg_id" { type = list(string) }
variable "subnet_id" { type = list(string) }
variable "subnet_cidr" { type = list(string) }
variable "instance_ip" { type = list(string) }
variable "lb_ip" { type = string }
variable "domain" { type = string }
variable "k3s_token" {
  type      = string
  sensitive = true
}
variable "tail_key" {
  type      = string
  sensitive = true
}
variable "crowdsec_key" {
  type      = string
  sensitive = true
}