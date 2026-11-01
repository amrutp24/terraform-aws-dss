# Assertions on the shape of the plan: who can reach DSS, and on what.
#
# The provider is mocked, so the AMI, VPC and subnet lookups return generated
# values and nothing reaches AWS. Everything asserted here comes from
# configuration rather than from the API, which is what makes that safe.
mock_provider "aws" {
  # The module picks the first subnet in the VPC when none is given. A bare
  # mock returns an empty list for that lookup and the index fails, so supply
  # one. The value is never used for anything but to exist.
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-0123456789abcdef0"]
    }
  }

  # The aws provider parses assume_role_policy rather than passing it through,
  # so a generated mock string is rejected as "not a JSON object". Give it a
  # policy that parses; its contents are never used.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  allowed_cidr_blocks = ["203.0.113.10/32"]
}

# The security group is the whole security story for this module. A rule that
# admitted a range nobody chose would be the worst bug it could have.
run "only_the_given_ranges_reach_dss" {
  command = plan

  variables {
    allowed_cidr_blocks = ["203.0.113.10/32", "198.51.100.0/24"]
  }

  assert {
    condition = length([
      for rule in aws_security_group.dss.ingress :
      rule if rule.from_port == 10000
    ]) == 1
    error_message = "Exactly one ingress rule should open the DSS port."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.dss.ingress :
      toset(rule.cidr_blocks) == toset(["203.0.113.10/32", "198.51.100.0/24"])
      if rule.from_port == 10000
    ])
    error_message = "The DSS rule must admit exactly the ranges given, and nothing else."
  }
}

run "the_dss_port_follows_the_variable" {
  command = plan

  variables {
    dss_port = 11000
  }

  assert {
    condition = length([
      for rule in aws_security_group.dss.ingress :
      rule if rule.from_port == 11000 && rule.to_port == 11000
    ]) == 1
    error_message = "Changing dss_port must move the ingress rule with it, or DSS answers on a port nothing can reach."
  }
}

# SSH is off unless asked for. An instance that quietly accepts SSH is a
# different security posture than the one the caller chose.
run "no_ssh_rule_unless_asked_for" {
  command = plan

  assert {
    condition = length([
      for rule in aws_security_group.dss.ingress :
      rule if rule.from_port == 22
    ]) == 0
    error_message = "SSH must be closed by default."
  }
}

run "ssh_opens_only_to_the_given_ranges" {
  command = plan

  variables {
    ssh_cidr_blocks = ["203.0.113.10/32"]
  }

  assert {
    condition = length([
      for rule in aws_security_group.dss.ingress :
      rule if rule.from_port == 22 && rule.to_port == 22
    ]) == 1
    error_message = "ssh_cidr_blocks is set and no SSH rule was planned."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.dss.ingress :
      toset(rule.cidr_blocks) == toset(["203.0.113.10/32"])
      if rule.from_port == 22
    ])
    error_message = "The SSH rule must admit exactly the ranges given."
  }
}

# The security group is replaced rather than edited, and a group still
# attached to an instance cannot be deleted. Without create_before_destroy a
# change that replaces it fails partway.
run "the_security_group_is_replaced_before_it_is_destroyed" {
  command = plan

  assert {
    condition     = startswith(aws_security_group.dss.name_prefix, var.name)
    error_message = "The group uses name_prefix so a replacement can exist alongside the one it replaces."
  }
}

# Dataiku asks for at least 16 GB. An instance too small installs and then
# fails under the first real workload.
run "the_instance_clears_dataikus_memory_floor" {
  command = plan

  assert {
    condition     = aws_instance.dss.instance_type == "m5.xlarge"
    error_message = "The default instance type should clear Dataiku's 16 GB floor."
  }
}

# Without this, and without a key pair, nothing can reach the host. That
# matters more than it sounds: the bootstrap writes an admin API key to disk
# at boot, and the dataiku provider needs it, so an unreachable host makes the
# second half of the workflow impossible.
run "no_iam_is_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.ssm) == 0 && length(aws_iam_instance_profile.ssm) == 0
    error_message = "A module left at its defaults must create no IAM."
  }

  # Not asserted: that the instance carries no profile. aws_instance's
  # iam_instance_profile is computed, so at plan time it is unknown and the
  # comparison cannot be evaluated. The absence of the role and the profile
  # above is the same fact, reached from the side that is knowable.
}

# Reading the licence needs an identity, so naming a parameter has to create
# one even with Session Manager off. Without this the instance would boot with
# no profile and the fetch would fail with a credentials error at install time.
run "a_licence_parameter_creates_an_instance_profile_on_its_own" {
  command = plan

  variables {
    license_ssm_parameter = "/dss/license"
  }

  assert {
    condition     = length(aws_iam_role.ssm) == 1 && length(aws_iam_instance_profile.ssm) == 1
    error_message = "Naming a licence parameter must create a role and an instance profile."
  }

  assert {
    condition     = length(aws_iam_role_policy.license_read) == 1
    error_message = "The role should carry a policy letting it read the licence."
  }

  # Session Manager was not asked for, so its policy must stay off. The two
  # features share a role and nothing else.
  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 0
    error_message = "A licence parameter must not quietly grant Session Manager access."
  }
}

# The licence must not travel through Terraform. If it is in the boot script
# it is in state and in instance metadata, which is the whole thing this
# avoids, so the script should carry the command and not a licence.
run "the_licence_is_fetched_on_the_instance_rather_than_rendered" {
  command = plan

  variables {
    license_ssm_parameter = "/dss/license"
  }

  assert {
    condition     = strcontains(module.bootstrap.install_script, "get_parameter(Name=sys.argv[2],WithDecryption=True)")
    error_message = "The boot script should read the licence from Parameter Store, decrypted."
  }

  assert {
    condition     = strcontains(module.bootstrap.install_script, "/dss/license")
    error_message = "The boot script should name the parameter it was given."
  }

  assert {
    condition     = !strcontains(module.bootstrap.install_script, "writing licence")
    error_message = "No licence content should be rendered into the boot script."
  }

  # Not the AWS CLI: Ubuntu 24.04 has no awscli package in any component, so
  # a fetch that shells out to it fails and DSS comes up unlicensed. Checked
  # on a running instance.
  assert {
    condition     = !strcontains(module.bootstrap.install_script, "aws ssm get-parameter")
    error_message = "The fetch must not depend on the AWS CLI, which this AMI cannot install."
  }

  assert {
    condition     = strcontains(module.bootstrap.install_script, "import boto3")
    error_message = "The fetch should read the parameter with boto3, which the Ubuntu image carries."
  }

  # The parameter and region arrive as argv, so the Python body needs no
  # quoting and a parameter name cannot terminate a string literal.
  assert {
    condition     = strcontains(module.bootstrap.install_script, "sys.argv[2]")
    error_message = "The parameter name should be passed as an argument rather than interpolated into the Python."
  }
}

run "no_licence_parameter_means_no_licence_policy" {
  command = plan

  variables {
    enable_ssm = true
  }

  assert {
    condition     = length(aws_iam_role_policy.license_read) == 0
    error_message = "Session Manager alone must not grant any parameter read."
  }
}

run "ssm_attaches_a_profile_to_the_instance" {
  command = plan

  variables {
    enable_ssm = true
  }

  assert {
    condition     = length(aws_iam_role.ssm) == 1
    error_message = "enable_ssm should create exactly one role."
  }

  assert {
    condition     = one(aws_iam_role_policy_attachment.ssm).policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The role should carry the policy AWS publishes for Session Manager, and not a hand-rolled one."
  }
}
