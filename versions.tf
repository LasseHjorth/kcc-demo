terraform {
  backend "gcs" {
    bucket = "dvt-lasse-kcc-demo-state"
    prefix = "terraform"
  }
}
