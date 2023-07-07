terraform {
  required_version = ">= 0.14.0"
  required_providers {
    # tflint-ignore: terraform_unused_required_providers
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
}
