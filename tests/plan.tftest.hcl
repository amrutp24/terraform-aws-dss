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
