variable "dss_version" {
  description = "DSS version to install, for example \"15.0.0\". Must exist under the download base URL."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.dss_version))
    error_message = "dss_version must look like 15.0.0."
  }
}

variable "dss_port" {
  description = "Base TCP port DSS listens on. DSS also uses a small range above this."
  type        = number
  default     = 10000

  validation {
    condition     = var.dss_port > 1024 && var.dss_port < 65000
    error_message = "dss_port must be an unprivileged port below 65000."
  }
}

variable "dss_user" {
  description = "Unix account DSS runs as. Created if missing. Never root."
  type        = string
  default     = "dataiku"

  validation {
    condition     = var.dss_user != "root"
    error_message = "DSS must not run as root."
  }
}

variable "install_dir" {
  description = "Where the DSS binaries are unpacked."
  type        = string
  default     = "/opt/dataiku"
}

variable "data_dir" {
  description = "DSS data directory. This holds all projects and configuration, so it is what you back up and what you put on a persistent disk."
  type        = string
  default     = "/data/dataiku/dss_data"
}

variable "download_base_url" {
  description = "Base URL the installer tarball is fetched from. Point this at an internal mirror for hosts without internet access."
  type        = string
  default     = "https://downloads.dataiku.com/public/studio"
}

variable "license_json" {
  description = <<-EOT
    Contents of a DSS licence file, applied at install time. Leave empty to
    register the instance through the browser instead.

    This lands in the rendered script, so it reaches Terraform state and
    whatever the script is passed to (instance metadata, user-data). Supply it
    from a secret store rather than a checked-in file.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "create_api_key" {
  description = "Whether the bootstrap mints an admin API key so Terraform can then configure the instance. Without it you have to create a key by hand before the dataiku provider can do anything."
  type        = bool
  default     = true
}

variable "api_key_label" {
  description = "Label given to the API key the bootstrap creates."
  type        = string
  default     = "terraform"
}

variable "api_key_path" {
  description = "Path on the host the created API key is written to, as JSON, mode 0600. How you retrieve it is platform-specific; see the module README."
  type        = string
  default     = "/var/lib/dataiku-terraform-key.json"
}
