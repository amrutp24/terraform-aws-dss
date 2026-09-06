# The module creates no infrastructure, so every check is a plan-time
# assertion on what the template rendered. That makes these tests fast and
# free: no provider, no credentials, nothing to destroy.

variables {
  dss_version = "15.0.0"
}

run "defaults_render_a_usable_script" {
  command = plan

  assert {
    condition     = startswith(output.install_script, "#!/usr/bin/env bash")
    error_message = "The script must start with a shebang to be usable as user-data."
  }

  assert {
    condition     = strcontains(output.install_script, "DSS_VERSION=\"15.0.0\"")
    error_message = "The requested version did not reach the script."
  }

  assert {
    condition     = strcontains(output.install_script, "https://downloads.dataiku.com/public/studio/$DSS_VERSION/$TARBALL")
    error_message = "The download URL is wrong; the installer would not be fetched."
  }

  assert {
    condition     = strcontains(output.install_script, "DSS_PORT=\"10000\"")
    error_message = "The default port did not reach the script."
  }

  assert {
    condition     = output.data_dir == "/data/dataiku/dss_data"
    error_message = "The data directory output does not match the default."
  }
}

run "refuses_to_reinstall_over_an_existing_instance" {
  command = plan

  # Cloud-init and startup scripts are re-run on reboot and on image rebuild,
  # so this guard is what stops a restart wiping a live data directory.
  assert {
    condition     = strcontains(output.install_script, "if [ -f \"$DATA_DIR/bin/dss\" ]; then")
    error_message = "The script must not reinstall over an existing data directory."
  }
}

run "never_runs_dss_as_root" {
  command = plan

  assert {
    condition     = strcontains(output.install_script, "sudo -u \"$DSS_USER\" \"$UNPACKED/installer.sh\"")
    error_message = "The installer must run as the service user, not as root."
  }
}

run "licence_is_written_and_passed_to_the_installer" {
  command = plan

  variables {
    license_json = "{\"licenseKind\":\"COMMUNITY\"}"
  }

  assert {
    condition     = strcontains(output.install_script, "{\"licenseKind\":\"COMMUNITY\"}")
    error_message = "The licence content was not written into the script."
  }

  assert {
    condition     = strcontains(output.install_script, "LICENSE_FLAG=\"-l $INSTALL_DIR/license.json\"")
    error_message = "A supplied licence must be passed to the installer with -l."
  }

  assert {
    condition     = strcontains(output.install_script, "-m 0600")
    error_message = "The licence file must not be world-readable."
  }
}

run "no_licence_means_no_licence_flag" {
  command = plan

  # license_json defaults to empty, so the conditional block must collapse
  # rather than emitting an empty -l flag that would break the installer.
  assert {
    condition     = strcontains(output.install_script, "LICENSE_FLAG=\"\"")
    error_message = "Without a licence the installer flag must be empty."
  }

  assert {
    condition     = !strcontains(output.install_script, "writing licence")
    error_message = "The licence block should not be rendered when none is supplied."
  }
}

run "api_key_is_created_by_default" {
  command = plan

  assert {
    condition     = strcontains(output.install_script, "dsscli\" api-key-create")
    error_message = "The bootstrap should mint the API key the provider needs."
  }

  assert {
    condition     = output.api_key_path == "/var/lib/dataiku-terraform-key.json"
    error_message = "The API key path output does not match the default."
  }

  assert {
    condition     = strcontains(output.install_script, "chmod 0600")
    error_message = "The API key file must not be world-readable."
  }
}

run "api_key_creation_can_be_turned_off" {
  command = plan

  variables {
    create_api_key = false
  }

  assert {
    condition     = !strcontains(output.install_script, "api-key-create")
    error_message = "No key should be created when create_api_key is false."
  }

  assert {
    condition     = output.api_key_path == null
    error_message = "api_key_path must be null when no key is created."
  }
}

run "waits_for_the_backend_before_using_dsscli" {
  command = plan

  # dsscli talks to the running backend, so minting a key immediately after
  # starting DSS races its startup.
  assert {
    condition     = strcontains(output.install_script, "waiting for the DSS backend")
    error_message = "The script must wait for the backend before calling dsscli."
  }
}

run "cloud_init_wraps_the_same_script" {
  command = plan

  assert {
    condition     = startswith(output.cloud_init, "#cloud-config")
    error_message = "cloud_init must be a cloud-config document."
  }

  assert {
    condition     = strcontains(output.cloud_init, "/opt/dss-bootstrap.sh")
    error_message = "cloud-init must write and then run the script."
  }

  assert {
    condition     = strcontains(output.cloud_init, "DSS_VERSION=\"15.0.0\"")
    error_message = "The script embedded in cloud-init lost its variables."
  }
}

run "custom_paths_and_port_are_honoured" {
  command = plan

  variables {
    dss_port          = 11000
    dss_user          = "dku"
    install_dir       = "/srv/dataiku"
    data_dir          = "/mnt/disks/dss"
    download_base_url = "https://mirror.internal/dss"
  }

  assert {
    condition = alltrue([
      strcontains(output.install_script, "DSS_PORT=\"11000\""),
      strcontains(output.install_script, "DSS_USER=\"dku\""),
      strcontains(output.install_script, "INSTALL_DIR=\"/srv/dataiku\""),
      strcontains(output.install_script, "DATA_DIR=\"/mnt/disks/dss\""),
      strcontains(output.install_script, "https://mirror.internal/dss/$DSS_VERSION/$TARBALL"),
    ])
    error_message = "A custom path, port or mirror did not reach the script."
  }

  assert {
    condition     = output.dss_port == 11000
    error_message = "The port output does not follow the variable."
  }
}
