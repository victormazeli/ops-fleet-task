# Create the state bucket and lock table in the production environment, i am only skipping this for now to use local state

# terraform {
#   backend "s3" {
#     bucket         = "ops-fleet-task-terraform-state"
#     key            = "eks-karpenter-demo/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "ops-fleet-task-terraform-lock-table"
#   }
# }

