provider "google" {
  project = "finance-sop-portal"
  region  = "us-central1"
  zone    = "us-central1-a"
}

# 1. Custom VPC Network for Lab Only
resource "google_compute_network" "lab_vpc" {
  name                    = "lab-ansible-network"
  auto_create_subnetworks = false
}

# 2. Lab Subnet
resource "google_compute_subnetwork" "lab_subnet" {
  name          = "lab-ansible-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.lab_vpc.id
}

# 3. Lab Firewall Rule
resource "google_compute_firewall" "lab_firewall" {
  name    = "lab-allow-web-and-ssh"
  network = google_compute_network.lab_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lab-http-server"]
}

# 4. Lab Storage Bucket
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "lab_storage" {
  name          = "lab-finance-sop-assets-${random_id.bucket_suffix.hex}"
  location      = "US"
  force_destroy = true
}

# 5. 3 Lab Web Servers
resource "google_compute_instance" "web_servers" {
  count        = 3
  name         = "lab-web-server-${count.index + 1}"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.lab_vpc.id
    subnetwork = google_compute_subnetwork.lab_subnet.id
    access_config {
      # Public IP
    }
  }

  tags = ["lab-http-server"]
}

output "server_ips" {
  value = google_compute_instance.web_servers[*].network_interface[0].access_config[0].nat_ip
}
