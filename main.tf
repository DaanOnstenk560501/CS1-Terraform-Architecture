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

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "public-subnet-2"
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

# Security Groups - Production VPC
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-security-group"
  }
}

resource "aws_security_group" "ecs_frontend_sg" {
  name        = "ecs-frontend-security-group"
  description = "Security group for ECS Frontend containers"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-frontend-security-group"
  }
}

resource "aws_security_group" "ecs_backend_sg" {
  name        = "ecs-backend-security-group"
  description = "Security group for ECS Backend containers"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_frontend_sg.id]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-backend-security-group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-security-group"
  }
}

# Security Groups - Shared Services VPC
resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-security-group"
  description = "Security group for Prometheus and Grafana"
  vpc_id      = aws_vpc.shared_services.id

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16", "10.2.0.0/16"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "monitoring-security-group"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "main-application-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false

  tags = {
    Name = "main-alb"
  }
}

# ALB Target Group for Frontend
resource "aws_lb_target_group" "frontend" {
  name     = "frontend-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.production.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "frontend-target-group"
  }
}

# ALB Listener
resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = {
    Name = "frontend-listener"
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

resource "aws_route_table_association" "public_2_association" {
  subnet_id      = aws_subnet.public_2.id
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