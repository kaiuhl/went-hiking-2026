variable "aws_region" {
  type        = string
  description = "AWS region for regional resources."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "Project tag/name prefix."
  default     = "went-hiking-2026"
}

variable "media_bucket_name" {
  type        = string
  description = "Private S3 bucket for migrated media."
  default     = "wenthiking-media-2026"
}

variable "lightsail_instance_name" {
  type        = string
  description = "Lightsail preview instance name."
  default     = "went-hiking-2026"
}

variable "lightsail_static_ip_name" {
  type        = string
  description = "Lightsail static IPv4 address name."
  default     = "went-hiking-2026-ip"
}

variable "lightsail_availability_zone" {
  type        = string
  description = "Lightsail instance availability zone."
  default     = "us-west-2a"
}

variable "lightsail_blueprint_id" {
  type        = string
  description = "Lightsail OS blueprint."
  default     = "ubuntu_24_04"
}

variable "lightsail_bundle_id" {
  type        = string
  description = "Lightsail bundle."
  default     = "nano_3_0"
}

variable "lightsail_key_pair_name" {
  type        = string
  description = "Existing Lightsail key pair used by the preview instance."
  default     = "went-hiking-2026-good-20260517234635"
}

variable "lightsail_user_data_path" {
  type        = string
  description = "Optional path to the Lightsail bootstrap script."
  default     = null
  nullable    = true
}

variable "manage_lightsail_static_ip" {
  type        = bool
  description = "Create and attach the Lightsail static IP. Keep false for the adopted preview because the AWS provider cannot import existing static IPs."
  default     = false
}

variable "manage_lightsail_public_ports" {
  type        = bool
  description = "Manage Lightsail public ports. Keep false for the adopted preview because the AWS provider cannot import existing public-port state."
  default     = false
}

variable "existing_lightsail_static_ip_address" {
  type        = string
  description = "Static IP address for the adopted preview when not managing static IP allocation in OpenTofu."
  default     = "35.160.199.53"
}
