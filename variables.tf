#provider
variable "api_fingerprint" { type = string }
variable "api_private_key_path" { type = string }
variable "tenancy_id" { type = string }
variable "user_id" { type = string }
variable "region" { type = string }
variable "region_ad" { type = string }

#app
variable "app_name" { type = string }

#vcn
variable "vcn_cidr" { type = list(string) }

#network
variable "net_border" { type = list(string) }
variable "net_secgroup" { type = list(string) }
variable "nsg_rule" { type = map(list(object({ min = number, max = number, type = number, direction = string, target = string, target_type = string, description = string }))) }

variable "subnet_cidr" { type = list(string) }

#instance
variable "instance_ip" { type = list(string) }
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