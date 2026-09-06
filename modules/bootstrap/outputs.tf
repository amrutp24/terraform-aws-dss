output "install_script" {
  description = "The rendered bootstrap script. Run it as root on any Linux host: pass it as EC2 user-data, a GCE startup script, an Azure custom script, a remote-exec payload, or a Packer provisioner."
  value       = local.install_script
  sensitive   = true # carries license_json when one was supplied
}

output "cloud_init" {
  description = "The same script wrapped as cloud-config, for targets that consume cloud-init directly."
  value       = local.cloud_init
  sensitive   = true
}

output "data_dir" {
  description = "DSS data directory on the host. Put a persistent disk here."
  value       = var.data_dir
}

output "dss_port" {
  description = "Port DSS listens on."
  value       = var.dss_port
}

output "api_key_path" {
  description = "Where the bootstrap wrote the admin API key, when create_api_key is set."
  value       = var.create_api_key ? var.api_key_path : null
}

output "url_path" {
  description = "Path to append to the host address to reach DSS, as a convenience for building the provider's host argument."
  value       = ":${var.dss_port}"
}
