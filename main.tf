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
  source  = "amrutp24/dss-bootstrap/null"
  version = "~> 0.3"

  dss_version  = var.dss_version
  dss_port     = var.dss_port
  data_dir     = var.data_dir
  license_json = var.license_json

  # Read on the instance, so no licence material reaches state or metadata.
  # The instance profile below grants this and nothing else.
  #
  # python3 and boto3 rather than the AWS CLI, which this AMI cannot provide:
  # Ubuntu 24.04 has no awscli package at all, in any component, so an
  # apt install of it fails with "no installation candidate". Checked on a
  # running instance rather than assumed. The CLI's own installer would work
  # but means a 60 MB download at boot, and an architecture to get right.
  #
  # boto3 arrives as python3-boto3, a dependency of sosreport, which is part
  # of the standard Ubuntu cloud image the AMI lookup above selects. It is
  # also in apt if it ever goes missing, which awscli is not.
  #
  # One command, not a list: the bootstrap redirects this command's stdout
  # into the licence file and its stderr into a log, and a list would
  # redirect only its last part. The region and parameter arrive as argv so
  # the Python needs no quoting of its own.
  license_fetch_command = var.license_ssm_parameter == null ? "" : join(" ", [
    "python3 -c 'import boto3,sys;print(boto3.client(\"ssm\",region_name=sys.argv[1]).get_parameter(Name=sys.argv[2],WithDecryption=True)[\"Parameter\"][\"Value\"])'",
    data.aws_region.current.region,
    var.license_ssm_parameter,
  ])
}

data "aws_region" "current" {}

locals {
  # Either feature needs the instance to have an identity of its own.
  needs_instance_profile = var.enable_ssm || var.license_ssm_parameter != null
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
  iam_instance_profile        = local.needs_instance_profile ? aws_iam_instance_profile.ssm[0].name : null

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

# ---------------------------------------------------------------------------
# Session Manager access
# ---------------------------------------------------------------------------

# Everything here is created only when enable_ssm is on or a licence
# parameter was named, so a module left at its defaults makes no IAM at all.

data "aws_iam_policy_document" "ssm_assume" {
  count = local.needs_instance_profile ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  count = local.needs_instance_profile ? 1 : 0

  name_prefix        = "${var.name}-ssm-"
  description        = "Identity for the Dataiku DSS instance: Session Manager, and reading its licence"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume[0].json
  tags               = var.tags
}

# AmazonSSMManagedInstanceCore is the policy AWS publishes for exactly this,
# so it is the right thing to attach rather than a hand-rolled copy. It is
# wider than its name suggests, though, and this comment used to claim the
# opposite: alongside the agent's own calls it grants ssm:GetParameter and
# ssm:GetParameters on Resource "*", so an instance with enable_ssm on can
# read every parameter in the account. Read off the live policy document, not
# assumed. enable_ssm says so too.
#
# That is also why the licence policy below is still worth having: it is what
# authorises the read when enable_ssm is off, and it keeps the licence working
# independently of what AWS chooses to put in a managed policy.
resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.enable_ssm ? 1 : 0

  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  count = local.needs_instance_profile ? 1 : 0

  name_prefix = "${var.name}-ssm-"
  role        = aws_iam_role.ssm[0].name
  tags        = var.tags
}

# ---------------------------------------------------------------------------
# Reading the licence
# ---------------------------------------------------------------------------

# Scoped to the one parameter named, rather than to the path or to every
# parameter in the account. A licence is not worth broader access than that.
data "aws_iam_policy_document" "license_read" {
  count = var.license_ssm_parameter != null ? 1 : 0

  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.license_ssm_parameter, "/")}",
    ]
  }
}

resource "aws_iam_role_policy" "license_read" {
  count = var.license_ssm_parameter != null ? 1 : 0

  name_prefix = "${var.name}-license-"
  role        = aws_iam_role.ssm[0].id
  policy      = data.aws_iam_policy_document.license_read[0].json
}

data "aws_caller_identity" "current" {}
