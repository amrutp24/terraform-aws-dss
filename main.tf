# Stands up a DSS instance on EC2 and leaves it ready to configure.
#
# This is layer one only. Configuring what is on the instance -- projects,
# groups, code environments -- is a separate apply, because Terraform builds a
# provider's configuration during planning and the dataiku provider needs a
# reachable instance and an API key before that. See README.md.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Ubuntu LTS, looked up rather than hardcoded: AMI ids differ per region and
# change whenever Canonical publishes a new build.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "selected" {
  id      = var.vpc_id == null ? null : var.vpc_id
  default = var.vpc_id == null ? true : null
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

module "bootstrap" {
  source = "github.com/amrutp24/terraform-null-dss-bootstrap?ref=v0.1.0"

  dss_version  = var.dss_version
  dss_port     = var.dss_port
  data_dir     = var.data_dir
  license_json = var.license_json
}

resource "aws_security_group" "dss" {
  name_prefix = "${var.name}-"
  description = "Dataiku DSS"
  vpc_id      = data.aws_vpc.selected.id

  # No default on allowed_cidr_blocks, so reaching DSS is always a decision
  # somebody made rather than something that happened.
  ingress {
    description = "DSS web interface and public API"
    from_port   = var.dss_port
    to_port     = var.dss_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.ssh_cidr_blocks == null ? [] : [1]
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidr_blocks
    }
  }

  egress {
    description = "DSS downloads its installer and code environment packages"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "dss" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id != null ? var.subnet_id : data.aws_subnets.selected.ids[0]
  key_name      = var.key_name

  vpc_security_group_ids      = [aws_security_group.dss.id]
  associate_public_ip_address = var.assign_public_ip

  # The data directory holds every project and all configuration, so it is
  # what you back up. It lives on the root volume here for simplicity; see the
  # note in README.md about moving it to its own EBS volume.
  root_block_device {
    volume_size           = var.disk_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data                   = module.bootstrap.install_script
  user_data_replace_on_change = false

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = merge(var.tags, { Name = var.name })
}
