terraform {
  required_providers {
    alis = {
      source = "alis-exchange/alis"
    }
  }
}

variable "alis_os_project" {
  type = string
}

variable "alis_region" {
  type = string
}

variable "alis_managed_spanner_project" {
  type = string
}

variable "alis_managed_spanner_instance" {
  type = string
}

variable "alis_managed_spanner_db" {
  type = string
}

variable "agent_service_name" {
  type = string
}

variable "neuron" {
  type = string
}

resource "google_cloud_run_service_iam_member" "operations_invoker" {
  service  = var.agent_service_name
  location = var.alis_region
  role     = "roles/run.invoker"
  member   = "serviceAccount:alis-build@${var.alis_os_project}.iam.gserviceaccount.com"
}

resource "google_cloud_tasks_queue" "operations" {
  name     = "${var.neuron}-operations"
  location = var.alis_region
}

resource "alis_google_spanner_table" "operations" {
  project         = var.alis_managed_spanner_project
  instance        = var.alis_managed_spanner_instance
  database        = var.alis_managed_spanner_db
  name            = "${replace(var.alis_os_project, "-", "_")}_${replace(var.neuron, "-", "_")}_Operations"
  prevent_destroy = false

  schema = {
    columns = [
      {
        name            = "key"
        is_computed     = true
        computation_ddl = "Operation.name"
        is_stored       = true
        type            = "STRING"
        is_primary_key  = true
        required        = true
        unique          = true
      },
      {
        name          = "Operation"
        type          = "PROTO"
        proto_package = "google.longrunning.Operation"
        required      = true
      },
      {
        name     = "State"
        type     = "BYTES"
        required = false
      },
      {
        name     = "ResumePoint"
        type     = "STRING"
        required = false
      },
      {
        name     = "UpdateTime"
        type     = "TIMESTAMP"
        required = true
      },
    ]
  }
}

# LRO operations are resumable workflow records, not permanent business data.
# TTL keeps completed/abandoned operations from accumulating indefinitely while
# still retaining recent state long enough for clients to poll or inspect them.
resource "alis_google_spanner_table_ttl_policy" "operations" {
  project  = alis_google_spanner_table.operations.project
  instance = alis_google_spanner_table.operations.instance
  database = alis_google_spanner_table.operations.database
  table    = alis_google_spanner_table.operations.name
  column   = "UpdateTime"
  ttl      = 90
}
