# The variable validations exist to fail at plan time rather than after an
# instance is already running. These check they fire.
#
# The provider is mocked. This module reads aws_ami, aws_vpc and aws_subnets,
# which are real API calls, so a plan needs either credentials or a mock. A
# mock keeps the suite runnable anywhere, and nothing asserted here depends on
# what those lookups return.
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

run "accepts_a_valid_configuration" {
  command = plan
}

run "rejects_an_empty_allowed_list" {
  command = plan

  variables {
    allowed_cidr_blocks = []
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "rejects_opening_dss_to_the_internet" {
  command = plan

  variables {
    allowed_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}
