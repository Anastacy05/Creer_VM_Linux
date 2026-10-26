terraform {
  required_providers {
    xenorchestra = {
      source  = "vatesfr/xenorchestra"
      version = "~> 0.29.0"
    }
  }
}

# =========================================================================
# CONNEXION XEN ORCHESTRA
# =========================================================================

provider "xenorchestra" {
  url      = "ws://127.0.0.1:80"
  username = "admin@admin.net"
  password = "admin"
  insecure = true
}

# =========================================================================
# RESSOURCES XCP-ng EXISTANTES
# =========================================================================

data "xenorchestra_pool" "pool" {
  name_label = "Pool"
}

data "xenorchestra_template" "template" {
  name_label = "Debian-Template-Base"
  pool_id    = data.xenorchestra_pool.pool.id
}

data "xenorchestra_sr" "sr_local" {
  name_label = "Local Storage"
  pool_id    = data.xenorchestra_pool.pool.id
}

data "xenorchestra_network" "vnet" {
  name_label = var.vnet_name
}

data "xenorchestra_host" "host" {
  name_label = var.host_name
}

# =========================================================================
# LOCALES
# =========================================================================

locals {

  hosts = [ "emilia", "ram", "rem"]

  node_id = index(local.hosts, var.host_name)

  gateways = [for k in range(1, var.gateway_number+1): cidrhost(var.gateways_cidr, k)]
  gateways_b64  = base64encode("${join("\n", local.gateways)}\n")

  script_b64    = base64encode(file("${path.root}/failover.sh"))
  
}

# =========================================================================
# VM
# =========================================================================

resource "xenorchestra_vm" "vm_linux" {

  name_label = var.vm_name
  name_description = "VM Debian créée avec Terraform"
  host = data.xenorchestra_host.host.id

  template = data.xenorchestra_template.template.id
  cpus       = var.cpus_number
  memory_max = var.memory_size * 1073741824

  hvm_boot_firmware = "bios"

  network {
      network_id  = data.xenorchestra_network.vnet.id
  }

  cloud_config = <<EOF
      #cloud-config

      hostname: ${var.vm_name}
      manage_etc_hosts: true

      write_files:
        - path: /etc/failover/node-id
          permissions: '0644'
          content: |
            ${local.node_id}
        - path: /etc/failover/gateways-list
          encoding: b64
          permissions: '0644'
          content: ${local.gateways_b64}
        - path: /usr/local/bin/failover.sh
          encoding: b64
          permissions: '0755'
          content: ${local.script_b64}
        - path: /etc/systemd/system/failover.service
          permissions: '0644'
          content: |
            [Unit]
            Description=Bascule de passerelle par defaut (VM cliente)
            Wants=network-online.target
            After=network-online.target
            ConditionPathExists=/etc/failover/gateways-list
            ConditionPathExists=/etc/failover/node-id
            [Service]
            Environment=IFACE=enX0
            ExecStart=/usr/local/bin/failover.sh
            Restart=always
            RestartSec=5
            [Install]
            WantedBy=multi-user.target

      runcmd:
        - systemctl daemon-reload
        - systemctl enable --now failover.service
  EOF

  cloud_network_config = <<EOF
      version: 1
      config:
      - type: physical
        name: enX0
        subnets:
          - type: dhcp
  EOF	

  disk {
    name_label = "${var.vm_name}-disk"
    sr_id      = data.xenorchestra_sr.sr_local.id
    size       = var.disk_size_gb * 1024 * 1024 * 1024
  }
  
}
