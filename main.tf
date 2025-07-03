module "vcn" {
  source         = "./modules/vcn"
  app_name       = var.app_name
  compartment_id = var.tenancy_id
  vcn_cidr       = var.vcn_cidr
}

module "network" {
  source         = "./modules/network"
  app_name       = var.app_name
  compartment_id = var.tenancy_id

  depends_on = [module.vcn]

  vcn_id = module.vcn.vcn_id

  net_border   = var.net_border
  net_secgroup = var.net_secgroup
  nsg_rule     = var.nsg_rule

  subnet_cidr = var.subnet_cidr
}

module "lb" {
  source         = "./modules/lb"
  app_name       = var.app_name
  compartment_id = var.tenancy_id
  subnet_id      = module.network.subnet_id

  depends_on = [module.network]

  vcn_id      = module.vcn.vcn_id
  nsg_id      = module.network.nsg_id
  instance_ip = var.instance_ip
}

module "instance" {
  source         = "./modules/instance"
  app_name       = var.app_name
  compartment_id = var.tenancy_id
  region_ad      = var.region_ad

  depends_on = [module.lb]

  vcn_id = module.vcn.vcn_id

  subnet_id    = module.network.subnet_id
  subnet_cidr  = var.subnet_cidr
  nsg_id       = module.network.nsg_id
  instance_ip  = var.instance_ip
  lb_ip        = module.lb.lb_ip[0]
  tail_key     = var.tail_key
  k3s_token    = var.k3s_token
  domain       = var.domain
  crowdsec_key = var.crowdsec_key
}