#######################################################################################################################
## ----------------------------------------------------------------------------------------------------------------- ##
## Terraform Root Module
## ------------------------------
## - 
## ----------------------------------------------------------------------------------------------------------------- ##
#######################################################################################################################
#BOF
terraform {
  # Terraform version required for this module to function
  required_version = "~> 1.2"
  # ---------------------------------------------------
  # Setup providers
  # ---------------------------------------------------
  required_providers {
    #
    google = {
      source  = "registry.terraform.io/hashicorp/google"
      version = "~> 4.40"
    }
    #
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.4"
    }
    #
    local = {
      source  = "registry.terraform.io/hashicorp/local"
      version = "~> 2.2"
    }
    #
    null = {
      source  = "registry.terraform.io/hashicorp/null"
      version = "~> 3.2"
    }
  } #END => required_providers
  # ---------------------------------------------------
  # Setup Backend
  # ---------------------------------------------------
  cloud {
    hostname = "app.terraform.io"
    #organization = <TF_CLOUD_ORGANIZATION>
    #tokne = <TF_TOKEN_*>
    #workspaces {
    #  name =  <TF_WORKSPACE>
    #}
  }
  # ---------------------------------------------------
} #END => terraform
## ---------------------------------------------------
## provider setup and authorization
## ---------------------------------------------------
provider "google" {
  # assign the project to execute within
  project = var.gcpProject
  # setup location
  region = var.gcpRegion
  zone   = var.gcpZone
}
provider "google-beta" {
  # assign the project to execute within
  project = var.gcpProject
  # setup location
  region = var.gcpRegion
  zone   = var.gcpZone
}
#######################################################################################################################
## ----------------------------------------------------------------------------------------------------------------- ##
## Local variable setup
## ----------------------------------------------------------------------------------------------------------------- ##
#######################################################################################################################
locals {
  ## ---------------------------------------------------
  instanceNetworkName    = "acme-corporation"
  instanceSubNetworkName = "management"
  instanceComputeImage = {
    "ubuntu-2204" = {
      "platform" = "linux"
      "project"  = "ubuntu-os-cloud"
      "x64" = {
        "family" = "ubuntu-2204-lts"
      }
      "arm" = {
        "family" = "notSupported"
      }
    }
  }
  ## ---------------------------------------------------
  computeInstances = flatten([for i, user in var.computeInstances : [
    for j, arch in user : [
      for k, os in arch : [
        for l in range(0, os["count"]) :
        {
          "name"     = lower(format("%s-%s-%s-%02s", i, j, k, l)),
          "key"      = lower(i),
          "instance" = l,
          "archType" = j,
          "osType"   = k
        }
      ]
    ]
    ]
  ])
  instanceConfig = { for i, data in local.computeInstances :
    data["name"] => {
      "config" = data,
      #
      "instanceId"           = i + 1,
      "instanceImageProject" = local.instanceComputeImage[data["osType"]]["platform"],
      "instanceImageProject" = local.instanceComputeImage[data["osType"]]["project"],
      "instanceImageFamily"  = local.instanceComputeImage[data["osType"]][data["archType"]]["family"]
    }
  }
  #
  builtComputeNumDataDisk = length(resource.google_compute_attached_disk.default) - 1
  buildComputerUsers  = join(", ", [for key in var.computeSshKeys : "${key.userId}"])
  builtComputeInstanceMap = { for i, data in local.instanceConfig :
    "${i}" => {
      "hostName" = resource.google_compute_instance.default[i].hostname
    "ipAddress" = resource.google_compute_instance.default[i].network_interface.0.access_config.0.nat_ip }
  }
  # map of all virtual machine instances created 
  ansibleInventoryFile = "../ansible/inventory.ini"
  # output data setup
  output_computeInstances = var.computeInstances
}
#######################################################################################################################
## ----------------------------------------------------------------------------------------------------------------- ##
## Data
## ----------------------------------------------------------------------------------------------------------------- ##
#######################################################################################################################
#
## ---------------------------------------------------
## ---------------------------------------------------
data "google_dns_managed_zone" "default" {
  name = local.instanceNetworkName
}
data "google_compute_network" "default" {
  name = local.instanceNetworkName
}
data "google_compute_subnetwork" "default" {
  name = format("%s-%s", data.google_compute_network.default.name, local.instanceSubNetworkName)
}
data "google_compute_image" "default" {
  for_each = local.instanceConfig
  #
  project = each.value["instanceImageProject"]
  family  = each.value["instanceImageFamily"]
}
data "google_compute_disk" "default" {
  for_each = local.instanceConfig
  #
  name = format("%s-%s-%02s", each.value["config"]["key"], var.computeEnvironment, each.value["config"]["instance"])
}
#######################################################################################################################
## ----------------------------------------------------------------------------------------------------------------- ##
## Resources
## ----------------------------------------------------------------------------------------------------------------- ##
#######################################################################################################################
#
resource "tls_private_key" "default" {
  algorithm = "ED25519"
}
resource "google_compute_address" "default" {
  for_each = local.instanceConfig
  #
  name         = resource.random_id.default[each.key].hex
  address_type = "EXTERNAL"
}
resource "random_id" "default" {
  for_each = local.instanceConfig
  #
  byte_length = 2
  prefix      = format("%s-", each.value["config"]["key"])
}
resource "google_dns_record_set" "default" {
  for_each = local.instanceConfig
  #
  name         = format("%s.%s", resource.random_id.default[each.key].hex, data.google_dns_managed_zone.default.dns_name)
  managed_zone = data.google_dns_managed_zone.default.name
  #
  type    = "A"
  ttl     = 300
  rrdatas = [resource.google_compute_address.default[each.key].address]
}
resource "google_compute_attached_disk" "default" {
  for_each = local.instanceConfig
  #
  disk     = data.google_compute_disk.default[each.key].id
  instance = resource.google_compute_instance.default[each.key].id
}
resource "google_compute_instance" "default" {
  for_each = local.instanceConfig
  lifecycle {
    ignore_changes = [attached_disk]
  }
  #
  name         = resource.random_id.default[each.key].hex
  machine_type = "f1-micro"
  #
  hostname = trimsuffix(resource.google_dns_record_set.default[each.key].name, ".")
  # 
  tags = [
    "subversion",
    var.computeEnvironment,
    "allow-ssh"
  ]
  metadata = {
    enable-oslogin         = false
    block-project-ssh-keys = true
    ssh-keys               = "build:${resource.tls_private_key.default.public_key_openssh}\n${join("\n", [for key in var.computeSshKeys : "${key.userId}:${key.publicKey}"])}"
  }

  boot_disk {
    initialize_params {
      # Returns the latest image that is part of an image family and is not deprecated
      image = data.google_compute_image.default[each.key].self_link
    }
  }

  network_interface {
    # use the provisioned VPC network
    network    = data.google_compute_network.default.name
    subnetwork = data.google_compute_subnetwork.default.name
    access_config {
      # assign the provisioned static IP address
      nat_ip = resource.google_compute_address.default[each.key].address
    }
  }

  provisioner "local-exec" {
    command = "echo INFO: ${self.name}"
  }

} # END => vmInstance
resource "google_compute_instance_group" "default" {
  lifecycle {
    create_before_destroy = true
  }
  name      = "instance-group"
  instances = flatten([for each in resource.google_compute_instance.default : each.self_link])

  named_port {
    name = "ssh"
    port = "22"
  }
}
resource "google_compute_firewall" "default" {
  for_each = local.instanceConfig
  #
  name    = format("%s-%s", resource.random_id.default[each.key].hex, "default")
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-ssh"]
}

resource "google_compute_firewall" "subversion" {
  for_each = local.instanceConfig
  #
  name    = format("%s-%s", resource.random_id.default[each.key].hex, "subversion")
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["3690"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["subversion"]
}
resource "google_compute_region_health_check" "default" {
  name = "health-check"

  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "22"
  }
}
resource "google_compute_region_backend_service" "default" {
  name = format("svn-%s", var.computeEnvironment)
  #
  load_balancing_scheme = "EXTERNAL"
  protocol              = "TCP"
  port_name             = "ssh"
  health_checks         = [resource.google_compute_region_health_check.default.id]
  #
  backend {
    balancing_mode = "CONNECTION"
    group          = resource.google_compute_instance_group.default.id
  }
}
resource "google_compute_forwarding_rule" "default" {
  name                  = format("svn-%s", var.computeEnvironment)
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "22"
  backend_service       = resource.google_compute_region_backend_service.default.id
  ip_address            = resource.google_compute_address.service.id
}

resource "google_compute_address" "service" {
  name = format("svn-%s", var.computeEnvironment)
  #
  address_type = "EXTERNAL"
}
resource "google_dns_record_set" "service" {
  name         = format("svn.%s", data.google_dns_managed_zone.default.dns_name)
  managed_zone = data.google_dns_managed_zone.default.name
  #
  type    = "A"
  ttl     = 300
  rrdatas = [resource.google_compute_address.service.address]
}
## ---------------------------------------------------
## ---------------------------------------------------
resource "local_file" "ansibleInventory" {
  # 
  content = <<-EOD
           #BOF
           [${var.computeProductKey}:vars]
           # variable configurations specific to the '${var.computeProductKey}' group
           computeEnvironment=${var.computeEnvironment}
           computeProductKey=${var.computeProductKey}
           computeNumDataDisk=${local.builtComputeNumDataDisk}
           computeUsers=${local.buildComputerUsers}
           
           [${var.computeProductKey}]
           # members of the '${var.computeProductKey}' group
           #%{for vmFqdn in local.builtComputeInstanceMap}
           ${lower(vmFqdn["hostName"])} ipAddress=${vmFqdn["ipAddress"]} %{endfor}
           #EOF
          EOD
  #
  filename        = local.ansibleInventoryFile
  file_permission = "0664"
  # show the file
  provisioner "local-exec" {
    #
    command = "cat ${local.ansibleInventoryFile}"
  }
}
## ---------------------------------------------------
## ---------------------------------------------------
resource "local_file" "openSshPrivateKey" {
  content = resource.tls_private_key.default.private_key_openssh
  #
  filename        = "../ansible/google_compute_engine"
  file_permission = "0600"
}
## ---------------------------------------------------
## ---------------------------------------------------
resource "null_resource" "productSetup" {
  for_each = local.builtComputeInstanceMap
  ## ----------------------------
  depends_on = [
    local_file.ansibleInventory,
  ]
  triggers = {
    "alwaysRun" = formatdate("YYYYMMDDhhmmss", timestamp()),
  }

  # general logging 
  provisioner "local-exec" {
    #
    command = "echo INFO: Virtual machine ${each.key}[${each.value["hostName"]}] setup completed"
  }
  # connection test
  provisioner "remote-exec" {
    #
    connection {
      type        = "ssh"
      user        = "build"
      private_key = resource.tls_private_key.default.private_key_openssh
      host        = each.value["hostName"] # connect using the FQDN
      # use the home directory of the remote(connection) user
      #script_path = "terraform_%RAND%.sh"
    }
    #
    inline = [
      "echo INFO: Virtual machine ${each.key}[${each.value["hostName"]}] connection test",
    ]
  }
  # execute Ansible Configuration as Code
  provisioner "local-exec" {
    #
    command = "cd ../ansible ; ansible-playbook --key-file ../ansible/google_compute_engine --inventory-file inventory.ini --limit ${each.value["hostName"]} playbook.yml"
  }
} #END => productSetup

#
#######################################################################################################################
## ----------------------------------------------------------------------------------------------------------------- ##
#######################################################################################################################
#EOF