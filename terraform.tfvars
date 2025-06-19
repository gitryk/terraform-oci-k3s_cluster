#provider
api_fingerprint      = ""
api_private_key_path = "./keys/terraform/private.pem"
region               = ""
region_ad            = ""
tenancy_id           = ""
user_id              = ""

#app
app_name = ""

#vcn
vcn_cidr = ["192.168.80.0/22"]

#network
net_border   = ["pub", "pri"]            #경계를 선언, public과 private로 구분
net_secgroup = ["lb", "worker", "tower"] #nsg를 LB, Worker, Tower(Bastion 역할)로 구분

domain = ""

nsg_rule = {
  "0" = [ #lb
    { min = 80, max = null, type = 6, direction = "INGRESS", target = "0.0.0.0/0", target_type = "CIDR_BLOCK", description = "Allow HTTP (EXT → LB)" },
    { min = 443, max = null, type = 6, direction = "INGRESS", target = "0.0.0.0/0", target_type = "CIDR_BLOCK", description = "Allow HTTPS (EXT → LB)" },
  ],
  "1" = [ #worker
    { min = 8080, max = null, type = 6, direction = "INGRESS", target = "0", target_type = "NETWORK_SECURITY_GROUP", description = "Allow HTTP (LB → Worker)" },
    { min = 8443, max = null, type = 6, direction = "INGRESS", target = "0", target_type = "NETWORK_SECURITY_GROUP", description = "Allow HTTPS (LB → Worker)" },

    { min = 1, max = 65535, type = 6, direction = "INGRESS", target = "1", target_type = "NETWORK_SECURITY_GROUP", description = "Allow Worker NSG TCP (Worker ↔ Worker)" },
    { min = 1, max = 65535, type = 17, direction = "INGRESS", target = "1", target_type = "NETWORK_SECURITY_GROUP", description = "Allow Worker NSG UDP (Worker ↔ Worker)" },

    { min = 22, max = null, type = 6, direction = "INGRESS", target = "2", target_type = "NETWORK_SECURITY_GROUP", description = "Allow SSH (Bastion → Worker)" },
    { min = 6443, max = null, type = 6, direction = "INGRESS", target = "2", target_type = "NETWORK_SECURITY_GROUP", description = "Allow API (Bastion → Worker)" },
    { min = 10250, max = null, type = 6, direction = "INGRESS", target = "2", target_type = "NETWORK_SECURITY_GROUP", description = "Allow API (Bastion → Worker)" },
  ],
  "2" = [ #tower
    { min = 22, max = null, type = 6, direction = "INGRESS", target = "100.64.0.0/10", target_type = "CIDR_BLOCK", description = "Allow Tailscale SSH (Tailscale → Bastion)" },
    { min = 80, max = null, type = 6, direction = "INGRESS", target = "100.64.0.0/10", target_type = "CIDR_BLOCK", description = "Allow Tailscale HTTP (Tailscale → Bastion)" },
    { min = 443, max = null, type = 6, direction = "INGRESS", target = "100.64.0.0/10", target_type = "CIDR_BLOCK", description = "Allow Tailscale HTTPS (Tailscale → Bastion)" },

    { min = 443, max = null, type = 6, direction = "INGRESS", target = "1", target_type = "NETWORK_SECURITY_GROUP", description = "Allow Worker HTTPS (Worker → Bastion)" },

    { min = 443, max = null, type = 6, direction = "EGRESS", target = "0.0.0.0/0", target_type = "CIDR_BLOCK", description = "Allow Tailscale Control Server (Bastion → Tailscale)" },
    { min = 41641, max = null, type = 17, direction = "INGRESS", target = "0.0.0.0/0", target_type = "CIDR_BLOCK", description = "Allow Tailscale DERP (Tailscale → Bastion)" },
    { min = 41641, max = null, type = 17, direction = "EGRESS", target = "0.0.0.0/0", target_type = "CIDR_BLOCK", description = "Allow Tailscale DERP (Bastion → Tailscale)" },
  ],
} #type 1 icmp, 6 tcp, 17 udp

subnet_cidr = ["192.168.82.0/25", "192.168.82.128/25"]

#instance
instance_ip = ["192.168.82.150", "192.168.82.151", "192.168.82.152", "192.168.82.200"]
tail_key    = ""
k3s_token   = ""
