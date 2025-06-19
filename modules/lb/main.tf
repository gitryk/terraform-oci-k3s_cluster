resource "oci_network_load_balancer_network_load_balancer" "this" {
    #Required
    compartment_id = var.compartment_id
    display_name = "${var.app_name}-lb"
    subnet_id = var.subnet_id[0]

    network_security_group_ids = [var.nsg_id[0]]
    is_private = false #공개 로드밸런서
    nlb_ip_version = "IPV4"

}

resource "oci_network_load_balancer_backend_set" "http" {
    health_checker {
        protocol = "TCP"
        port = 8080
    }
    name = "${var.app_name}-bendset-http"
    network_load_balancer_id = oci_network_load_balancer_network_load_balancer.this.id
    policy = "FIVE_TUPLE"
    depends_on = [oci_network_load_balancer_network_load_balancer.this]
}

resource "oci_network_load_balancer_backend_set" "https" {
    health_checker {
        protocol = "TCP"
        port = 8443
    }
    name = "${var.app_name}-bendset-https"
    network_load_balancer_id = oci_network_load_balancer_network_load_balancer.this.id
    policy = "FIVE_TUPLE"
    depends_on = [oci_network_load_balancer_network_load_balancer.this]
}

resource "oci_network_load_balancer_listener" "http" {
    default_backend_set_name = oci_network_load_balancer_backend_set.http.name
    network_load_balancer_id = oci_network_load_balancer_network_load_balancer.this.id
    name = "${var.app_name}-listener-http"
    protocol = "TCP"
    port = 80
    depends_on = [oci_network_load_balancer_backend_set.http]
}

resource "oci_network_load_balancer_listener" "https" {
    default_backend_set_name = oci_network_load_balancer_backend_set.https.name
    network_load_balancer_id = oci_network_load_balancer_network_load_balancer.this.id
    name = "${var.app_name}-listener-https"
    protocol = "TCP"
    port = 443
    depends_on = [oci_network_load_balancer_backend_set.https]
}

resource "oci_network_load_balancer_backend" "http" {
    count = length(var.instance_ip) - 1
    backend_set_name = oci_network_load_balancer_backend_set.http.name
    network_load_balancer_id = oci_network_load_balancer_network_load_balancer.this.id
    port = 8080

    ip_address = var.instance_ip[count.index]
    depends_on = [oci_network_load_balancer_backend_set.http]
}

resource "oci_network_load_balancer_backend" "https" {
    count = length(var.instance_ip) - 1
    backend_set_name = oci_network_load_balancer_backend_set.https.name
    network_load_balancer_id = oci_network_load_balancer_network_load_balancer.this.id
    port = 8443

    ip_address = var.instance_ip[count.index]
    depends_on = [oci_network_load_balancer_backend_set.https]
}