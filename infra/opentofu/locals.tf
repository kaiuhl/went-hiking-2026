data "aws_caller_identity" "current" {}

locals {
  media_origin_id = "${var.media_bucket_name}-s3-origin"

  tags = {
    Project   = "Went Hiking"
    ManagedBy = "OpenTofu"
    App       = var.project_name
  }
}
