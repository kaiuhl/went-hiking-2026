output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.media.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.media.domain_name
}

output "lightsail_static_ip" {
  value = var.manage_lightsail_static_ip ? aws_lightsail_static_ip.web[0].ip_address : var.existing_lightsail_static_ip_address
}

output "media_bucket_name" {
  value = aws_s3_bucket.media.bucket
}
