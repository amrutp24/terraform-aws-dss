# The variable validations exist to fail at plan time rather than halfway
# through a boot script on a machine nobody is watching. These check they
# actually fire.

variables {
  dss_version = "15.0.0"
}

run "rejects_a_version_that_is_not_semver" {
  command = plan

  variables {
    dss_version = "latest"
  }

  expect_failures = [var.dss_version]
}

run "rejects_a_partial_version" {
  command = plan

  variables {
    # The download URL is built from this, so "15.0" would 404 at boot.
    dss_version = "15.0"
  }

  expect_failures = [var.dss_version]
}

run "refuses_to_run_dss_as_root" {
  command = plan

  variables {
    dss_user = "root"
  }

  expect_failures = [var.dss_user]
}

run "rejects_a_privileged_port" {
  command = plan

  variables {
    # DSS runs unprivileged, so it could not bind this anyway.
    dss_port = 80
  }

  expect_failures = [var.dss_port]
}

run "rejects_a_port_above_the_valid_range" {
  command = plan

  variables {
    dss_port = 70000
  }

  expect_failures = [var.dss_port]
}

run "accepts_a_valid_configuration" {
  command = plan

  variables {
    dss_version = "14.7.0"
    dss_port    = 10000
    dss_user    = "dataiku"
  }

  assert {
    condition     = strcontains(output.install_script, "DSS_VERSION=\"14.7.0\"")
    error_message = "A valid configuration should render without complaint."
  }
}
