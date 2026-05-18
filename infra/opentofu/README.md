# Went Hiking Infrastructure

OpenTofu owns the AWS resources for the Went Hiking V2 preview:

- Lightsail instance, static IP, public ports, and static IP attachment
- Private S3 media bucket, versioning, and public access block
- CloudFront Origin Access Control and distribution for private photo reads
- S3 bucket policy scoped to CloudFront reads under `system/images/*`

## Adopt Existing Preview Resources

The first preview was bootstrapped manually. Adopt it before applying changes:

```sh
cd infra/opentofu
tofu init
cp terraform.tfvars.example terraform.tfvars
./import-existing.sh
tofu plan
```

Do not run `tofu apply` until the plan shows only expected tag/config drift.

## Current Preview IDs

- S3 bucket: `wenthiking-media-2026`
- CloudFront distribution: `E2502Q91SXFH32`
- CloudFront domain: `dec9ewwuufbq2.cloudfront.net`
- CloudFront OAC: `E2SDYZBFMCG2SJ`
- Lightsail instance: `went-hiking-2026`
- Lightsail static IP: `went-hiking-2026-ip`

## Lightsail Import Limitation

The AWS provider can import the Lightsail instance, but not the existing
Lightsail static IP or public-port resource state. For this adopted preview,
leave `manage_lightsail_static_ip=false` and `manage_lightsail_public_ports=false`.
For a fresh environment, set both to `true` so OpenTofu creates and owns them.

## State

Local state is ignored by git. Move this to a remote backend before more people
or agents manage the same resources.
