variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "allowed_cidr_blocks" {
  description = "Who may reach the DSS port, for example your office range."
  type        = list(string)
}
