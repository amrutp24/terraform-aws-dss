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
  description = "Give the instance a public address. False needs a route of your own: VPN, Direct Connect, or a bastion."
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

variable "license_ssm_parameter" {
  description = <<-EOT
    Name of an SSM Parameter Store parameter holding a DSS licence, which the
    instance reads for itself at boot.

    Prefer this over license_json. license_json is rendered into the boot
    script, so it reaches Terraform state and instance metadata, and anybody
    with ec2:DescribeInstanceAttribute can read it back. This puts only the
    parameter name in both places, and grants the instance ssm:GetParameter on
    that one parameter.

    Store it as a SecureString. With the default aws/ssm key that is all the
    setup required; a customer-managed key needs kms:Decrypt on the key added
    to the role as well, which this module does not do for you.

    Setting this creates an instance profile even when enable_ssm is off,
    because the instance cannot read a parameter without one.
  EOT
  type        = string
  default     = null
}

variable "enable_ssm" {
  description = <<-EOT
    Attach an IAM role that lets you reach the instance through AWS Systems
    Manager Session Manager.

    Off by default, because it is the one thing this module creates outside
    the VPC and somebody should choose it. Turn it on and you get a shell
    without a key pair and without opening port 22:

      aws ssm start-session --target <instance-id>

    This is also the only way to read the API key the bootstrap writes when
    create_api_key is on. Without either this or key_name, that file exists on
    the host and nothing can reach it, which makes the second half of the
    workflow, pointing the dataiku provider at the instance, impossible.

    Ubuntu 24.04 ships the SSM agent, so nothing is installed for this; only
    the instance profile is missing.
  EOT
  type        = bool
  default     = false
}
