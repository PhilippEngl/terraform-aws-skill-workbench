module "skills_key" {
  source = "./modules/kms-key"

  name        = "${local.name}-skills"
  description = "Encrypts authored and shared skills, and the harness's managed memory"

  deletion_window_in_days = 7

  tags = var.tags
}

module "skill_bucket" {
  source = "./modules/s3-bucket"

  name               = local.skill_bucket_name
  kms_key_arn        = module.skills_key.key_arn
  force_destroy      = true
  versioning_enabled = true

  # Off unless a caller names a bucket. The module does not create a log destination: doing
  # so cost seven resources for a signal that is narrow here, because every in-band request
  # arrives as the proxy Lambda's role. See the variable's description.
  logging_target_bucket = var.access_log_bucket_name
  logging_target_prefix = var.access_log_bucket_name != null ? "s3/${local.skill_bucket_name}/" : null

  cors_rules = [
    {
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = concat(["https://*.amplifyapp.com"], var.frontend_dev_origins)
      allowed_headers = ["*"]
    }
  ]

  tags = var.tags
}

# --- Curated skills -----------------------------------------------------------
# Terraform-managed, read only by the harness. These are the skills a platform team
# would curate: every user gets them, nobody can edit them from the browser. Replace
# the contents of skills/ with your own; the packaging below needs no changes.
resource "aws_s3_object" "shared_skill" {
  for_each = fileset("${path.module}/skills", "**")

  bucket = module.skill_bucket.bucket_id
  key    = "${local.shared_prefix}/${each.value}"
  source = "${path.module}/skills/${each.value}"

  source_hash = filemd5("${path.module}/skills/${each.value}")

  tags = merge(var.tags, {
    Name = "${local.shared_prefix}/${each.value}"
  })
}
