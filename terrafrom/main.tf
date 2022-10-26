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
  } #END => required_providers
  # ---------------------------------------------------
  # Setup Backend
  # ---------------------------------------------------
  cloud {
    hostname = "app.terraform.io"
    #organization = "dkp-acme-corporation"
    workspaces {
      tags = ["app"]
      #name = "terraform-google-subversion"
    }
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
    ssh-keys               = join("\n", [for key in var.computeSshKeys : "${key.userId}:${key.publicKey}"])
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
    command = "echo ${self.name}"
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
resource "google_compute_health_check" "default" {
  name = "health-check"

  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "22"
  }
}
resource "google_compute_backend_service" "default" {
  name = format("svn-%s", var.computeEnvironment)
  #
  load_balancing_scheme = "INTERNAL_SELF_MANAGED"
  protocol              = "TCP"
  port_name = "ssh"
  health_checks         = [resource.google_compute_health_check.default.id]
  #
  backend {
    balancing_mode  = "CONNECTION"
    group           = resource.google_compute_instance_group.default.id
    max_connections  = 2
  }
}
resource "google_compute_global_forwarding_rule" "default" {
  name                  = format("svn-%s", var.computeEnvironment)
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "22"
  target                = resource.google_compute_target_tcp_proxy.default.id
  ip_address            = resource.google_compute_global_address.default.id
}

resource "google_compute_target_tcp_proxy" "default" {
  lifecycle {
    create_before_destroy = true
  }
  name            = format("svn-%s", var.computeEnvironment)
  proxy_bind      = true
  backend_service = resource.google_compute_backend_service.default.id
}

resource "google_compute_global_address" "default" {
  name = format("svn-%s", var.computeEnvironment)
  #
  address_type = "EXTERNAL"
}
#
#######################################################################################################################
## ----------------------------------------------------------------------------------------------------------------- ##
#######################################################################################################################
#EOF