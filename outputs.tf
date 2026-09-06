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
