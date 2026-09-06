variable "name" {
  description = "Name applied to the instance and its security group."
  type        = string
  default     = "dataiku-dss"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type. DSS drops into a low-memory mode below roughly 16 GB and
    says so in its logs, so m5.xlarge is about the smallest that behaves
    normally.
  EOT
  type        = string
  default     = "m5.xlarge"
}

variable "allowed_cidr_blocks" {
  description = <<-EOT
    Who may reach the DSS port. Deliberately has no default: DSS holds your
    data and its login page would otherwise be open to the internet.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "Name at least one CIDR block that should reach DSS."
  }

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "0.0.0.0/0 exposes DSS to the whole internet. Use your own range, or edit this validation if you genuinely mean it."
  }
}

variable "ssh_cidr_blocks" {
  description = "Who may reach SSH. Null closes port 22 entirely, which is fine if you use SSM or never need a shell."
  type        = list(string)
  default     = null
}

variable "key_name" {
  description = "Existing EC2 key pair for SSH. Null if you do not need shell access."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC to launch into. Null uses the account's default VPC."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Subnet to launch into. Null picks the first subnet in the VPC, which is fine for a trial and not for production."
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "Give the instance a public address. False needs a route of your own -- VPN, Direct Connect, a bastion."
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Root volume size. DSS itself is about 10 GB unpacked; the rest is your projects and code environments."
  type        = number
  default     = 100
}

variable "dss_version" {
  description = "DSS version to install."
  type        = string
  default     = "15.0.0"
}

variable "dss_port" {
  description = "Port DSS listens on."
  type        = number
  default     = 10000
}

variable "data_dir" {
  description = "DSS data directory on the instance."
  type        = string
  default     = "/data/dataiku/dss_data"
}

variable "license_json" {
  description = "Contents of a DSS licence file, applied at install time. Reaches instance user-data and Terraform state, so pass it from a secret store."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to everything created here."
  type        = map(string)
  default     = {}
}
