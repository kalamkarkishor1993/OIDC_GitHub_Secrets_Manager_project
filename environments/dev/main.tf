terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "kalamkarkishor-terraform-state"
    key    = "dev/terraform.tfstate"    # आधी "terraform-aws-project/terraform.tfstate" होतं
    region = "ap-south-1"
    }
}

provider "aws" {
  region = "ap-south-1"
}