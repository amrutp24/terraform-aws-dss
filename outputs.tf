output "instance_id" {
  description = "EC2 instance id."
  value       = aws_instance.dss.id
}

output "public_ip" {
  description = "Public address, when one was assigned."
  value       = aws_instance.dss.public_ip
}

output "private_ip" {
  description = "Address within the VPC."
  value       = aws_instance.dss.private_ip
}

output "dss_url" {
  description = "Where DSS will answer once it has finished installing. Allow several minutes on first boot: the installer downloads about two gigabytes."
  value       = "http://${coalesce(aws_instance.dss.public_ip, aws_instance.dss.private_ip)}:${var.dss_port}"
}

output "data_dir" {
  description = "DSS data directory on the instance. This is what to back up."
  value       = var.data_dir
}

output "session_command" {
  description = <<-EOT
    How to get a shell on the instance, when enable_ssm is on. Null otherwise,
    which is the signal that nothing can reach the host: neither this nor a
    key pair was asked for.
  EOT
  value       = var.enable_ssm ? "aws ssm start-session --target ${aws_instance.dss.id}" : null
}

output "instance_profile_name" {
  description = <<-EOT
    The instance profile attached for Session Manager, or null when
    enable_ssm is off.

    Worth knowing: attaching a profile to an instance that is already
    running does not make Session Manager work straight away. The agent
    has to pick up the new credentials, and until it does, send-command
    answers "Instances not in a valid state for account".
  EOT
  value       = local.needs_instance_profile ? aws_iam_instance_profile.ssm[0].name : null
}

output "api_key_path" {
  description = <<-EOT
    Where the bootstrap wrote the admin API key, which is what the dataiku
    provider needs. Reading it takes a shell on the host, so this is null
    unless enable_ssm is on or you set key_name.

    Deliberately a path rather than a command. A command would have to carry
    the CLI profile and region, and this module is given neither: they are
    provider configuration, which a module cannot see. The caller knows them,
    so the caller builds the command.
  EOT
  value       = var.enable_ssm || var.key_name != null ? "/var/lib/dataiku-terraform-key.json" : null
}
