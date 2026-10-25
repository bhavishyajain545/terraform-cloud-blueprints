# Remote state - example only. Uncomment and fill in to use an S3 backend.
#
# Recommended setup for the state bucket (created once by a bootstrap stack):
#   - versioning on, SSE-KMS with a dedicated key, Block Public Access on, TLS-only bucket policy.
#   - The CI role may only read/write its own key prefix.
#
# Locking: Terraform >= 1.10 supports S3-native lock files (use_lockfile). A DynamoDB table
# is the classic approach and is shown for teams still on it; keep one of the two.
#
# terraform {
#   backend "s3" {
#     bucket       = "example-tfstate-111122223333-eu-west-1"
#     key          = "aws-dev/platform.tfstate"
#     region       = "eu-west-1"
#     encrypt      = true
#     kms_key_id   = "alias/tfstate"
#     use_lockfile = true # S3-native locking (Terraform >= 1.10)
#
#     # Classic DynamoDB locking (table with partition key "LockID", type String):
#     # dynamodb_table = "terraform-locks"
#   }
# }
