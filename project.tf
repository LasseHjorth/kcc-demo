resource "random_string" "suffix" {
  length           = 4
  special          = false
  numeric          = true
  lower = true
  upper = false
}

resource "google_project" "project" {
  project_id = "lasse-dvt-kcc-${random_string.suffix.result}"
  name       = "lasse-dvt-kcc-${random_string.suffix.result}"
  folder_id  = "866872219046"
  billing_account = "01C121-668AE6-16182A"
  deletion_policy = "DELETE"
}

resource "google_project_service" "apis" {
    for_each = toset(["compute.googleapis.com","container.googleapis.com"])
    service = each.key
    project = google_project.project.project_id
    disable_dependent_services = true
}


resource "google_compute_network" "vpc" {
    name = "kcc-vpc"
    project = google_project.project.project_id   
    depends_on = [google_project_service.apis["compute.googleapis.com"]]
}

resource "google_compute_subnetwork" "primary_subnet" {
    name = "primary-subnet"
    network = google_compute_network.vpc.id
    ip_cidr_range = "10.0.0.0/24"
    private_ip_google_access = true
    project = google_project.project.project_id
    region = var.default_region
}

resource "google_compute_firewall" "rules" {
  project = google_project.project.project_id
  name        = "allow-http"
  network = google_compute_network.vpc.id
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["http-server"]
  priority = 1000

  allow {
    protocol  = "tcp"
    ports     = ["80"]
  }

}

resource "google_compute_router" "router" {
  name    = "kcc-router"
  project = google_project.project.project_id
  region  = google_compute_subnetwork.primary_subnet.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "kcc-nat"
  project = google_project.project.project_id
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  enable_dynamic_port_allocation      = true
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}



resource "google_service_account" "gke" {
  account_id   = "gke-sa"
  project = google_project.project.project_id
  display_name = "Service Account GKE"
}

resource "google_project_iam_member" "gke_metric_writer" {
    project = google_project.project.project_id
    role    = "roles/monitoring.metricWriter"
    member  = "serviceAccount:${google_service_account.gke.email}"
}

resource "google_project_iam_member" "gke_log_writer" {
    project = google_project.project.project_id
    role    = "roles/logging.logWriter"
    member  = "serviceAccount:${google_service_account.gke.email}"
}

resource "google_container_cluster" "primary" {
  name     = "kcc-demo"
  location = var.default_region
  project  = google_project.project.project_id
  network = google_compute_network.vpc.id
  deletion_protection = false
  subnetwork = google_compute_subnetwork.primary_subnet.id
  initial_node_count       = 1
  private_cluster_config {
    enable_private_nodes = true
  }
  node_config {
    machine_type = "e2-standard-2"
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.gke.email
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  workload_identity_config {
    workload_pool = "${google_project.project.project_id}.svc.id.goog"
  }
  addons_config {
    config_connector_config {
        enabled = true
    }
  }
}

resource "google_service_account" "config_connector" {
  account_id   = "config-connector"
  project = google_project.project.project_id
  display_name = "Service Account config-connector"
}

resource "google_project_iam_member" "config_connector_edit" {
    project = google_project.project.project_id
    role    = "roles/editor"
    member  = "serviceAccount:${google_service_account.config_connector.email}"
}

resource "google_service_account_iam_member" "config_connector_workload_identity" {
    service_account_id = google_service_account.config_connector.id
    role = "roles/iam.workloadIdentityUser"
    member = "serviceAccount:${google_project.project.project_id}.svc.id.goog[cnrm-system/cnrm-controller-manager]"
    depends_on = [google_container_cluster.primary]
}

resource "local_file" "configconnecter_yaml" {
  content  = templatefile("templates/configconnecter.yaml.tftpl",{ project_id=google_project.project.project_id,sa_email=google_service_account.config_connector.email })
  filename = "config_connector/configconnecter.yaml"
}

resource "local_file" "computeinstance_yaml" {
  content  = templatefile("templates/computeinstance.yaml.tftpl",{ project_id=google_project.project.project_id,subnet=google_compute_subnetwork.primary_subnet.id })
  filename = "computeinstance/computeinstance.yaml"
}