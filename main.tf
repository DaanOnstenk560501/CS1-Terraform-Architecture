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

# Shared Services VPC (for monitoring)
resource "aws_vpc" "shared_services" {
  cidr_block           = "10.2.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "shared-services-vpc"
  }
}

# Production VPC Subnets
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "private_app_1" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-app-subnet-1"
  }
}

resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.21.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-db-subnet-1"
  }
}

# Shared Services VPC Subnets
resource "aws_subnet" "shared_public_1" {
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = "10.2.1.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "shared-public-subnet-1"
  }
}

resource "aws_subnet" "shared_private_1" {
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = "10.2.11.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "shared-private-subnet-1"
  }
}

# Internet Gateways
resource "aws_internet_gateway" "production_igw" {
  vpc_id = aws_vpc.production.id

  tags = {
    Name = "production-igw"
  }
}

resource "aws_internet_gateway" "shared_services_igw" {
  vpc_id = aws_vpc.shared_services.id

  tags = {
    Name = "shared-services-igw"
  }
}

# Transit Gateway
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Main Transit Gateway Hub"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name = "main-transit-gateway"
  }
}

# Transit Gateway VPC Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "production_attachment" {
  subnet_ids         = [aws_subnet.private_app_1.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id

  tags = {
    Name = "production-tgw-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services_attachment" {
  subnet_ids         = [aws_subnet.shared_private_1.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared_services.id

  tags = {
    Name = "shared-services-tgw-attachment"
  }
}

# Production VPC Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.production_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block         = "10.2.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Shared Services VPC Route Tables
resource "aws_route_table" "shared_public_rt" {
  vpc_id = aws_vpc.shared_services.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.shared_services_igw.id
  }

  tags = {
    Name = "shared-public-route-table"
  }
}

resource "aws_route_table" "shared_private_rt" {
  vpc_id = aws_vpc.shared_services.id

  route {
    cidr_block         = "10.1.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    Name = "shared-private-route-table"
  }
}

# Production VPC Route Table Associations
resource "aws_route_table_association" "public_1_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_app_1_association" {
  subnet_id      = aws_subnet.private_app_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_db_1_association" {
  subnet_id      = aws_subnet.private_db_1.id
  route_table_id = aws_route_table.private_rt.id
}

# Shared Services VPC Route Table Associations
resource "aws_route_table_association" "shared_public_1_association" {
  subnet_id      = aws_subnet.shared_public_1.id
  route_table_id = aws_route_table.shared_public_rt.id
}

resource "aws_route_table_association" "shared_private_1_association" {
  subnet_id      = aws_subnet.shared_private_1.id
  route_table_id = aws_route_table.shared_private_rt.id
}