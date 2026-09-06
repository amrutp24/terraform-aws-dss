# This module renders the DSS install script and nothing else. It declares no
# provider and creates no infrastructure, which is what keeps it usable against
# any target: a cloud VM's user-data, an on-prem host over SSH, or a machine
# image build.

terraform {
  required_version = ">= 1.5"
}

locals {
  install_script = templatefile("${path.module}/templates/install-dss.sh.tftpl", {
    dss_version       = var.dss_version
    dss_port          = var.dss_port
    dss_user          = var.dss_user
    install_dir       = var.install_dir
    data_dir          = var.data_dir
    download_base_url = var.download_base_url
    license_json      = var.license_json
    create_api_key    = var.create_api_key
    api_key_label     = var.api_key_label
    api_key_path      = var.api_key_path
  })

  # cloud-init runs the same script; wrapping it this way is what lets the
  # major clouds consume it directly as user-data.
  cloud_init = <<-EOT
    #cloud-config
    write_files:
      - path: /opt/dss-bootstrap.sh
        permissions: '0700'
        owner: root:root
        content: |
          ${indent(10, local.install_script)}
    runcmd:
      - [ /opt/dss-bootstrap.sh ]
  EOT
}
