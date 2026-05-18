#!/usr/bin/env bash
set -euo pipefail

# Adopt the manually bootstrapped preview resources into local OpenTofu state.
# Run from this directory after `tofu init`.

tofu import aws_s3_bucket.media wenthiking-media-2026
tofu import aws_s3_bucket_versioning.media wenthiking-media-2026
tofu import aws_s3_bucket_public_access_block.media wenthiking-media-2026
tofu import aws_s3_bucket_policy.media wenthiking-media-2026
tofu import aws_cloudfront_origin_access_control.media E2SDYZBFMCG2SJ
tofu import aws_cloudfront_distribution.media E2502Q91SXFH32
tofu import aws_lightsail_instance.web went-hiking-2026

cat <<'MSG'

Imported core resources.

The AWS provider currently does not support importing Lightsail static IPs or
instance public-port resources. For the adopted preview, keep
`manage_lightsail_static_ip=false` and `manage_lightsail_public_ports=false`.
Set them to true only for a fresh environment where OpenTofu creates those
resources from scratch.

MSG
