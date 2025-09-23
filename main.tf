terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# Production VPC
resource "aws_vpc" "production" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "production-vpc"
  }
}

# Public Subnet (for Load Balancer)
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "public-subnet-1"
  }
}

# Private Subnet (for ECS containers)
resource "aws_subnet" "private_app_1" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-app-subnet-1"
  }
}

# Private Subnet (for database)
resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.21.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-db-subnet-1"
  }
}