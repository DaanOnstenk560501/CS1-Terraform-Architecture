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

resource "aws_subnet" "shared_public_2" {
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = "10.2.2.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "shared-public-subnet-2"
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

# NAT Gateway for private subnets
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "nat-gateway-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "main-nat-gateway"
  }

  depends_on = [aws_internet_gateway.production_igw]
}

# NAT Gateway for Shared Services VPC
resource "aws_eip" "shared_nat_eip" {
  domain = "vpc"
  tags = {
    Name = "shared-nat-gateway-eip"
  }
}

resource "aws_nat_gateway" "shared" {
  allocation_id = aws_eip.shared_nat_eip.id
  subnet_id     = aws_subnet.shared_public_1.id

  tags = {
    Name = "shared-nat-gateway"
  }

  depends_on = [aws_internet_gateway.shared_services_igw]
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

resource "aws_security_group" "postgres_sg" {
  name        = "postgres-security-group"
  description = "Security group for PostgreSQL container"
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
    Name = "postgres-security-group"
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

# Security group for Grafana ALB
resource "aws_security_group" "grafana_alb_sg" {
  name        = "grafana-alb-security-group"
  description = "Security group for Grafana Load Balancer"
  vpc_id      = aws_vpc.shared_services.id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "grafana-alb-security-group"
  }
}

# Security group rule to allow ALB access to Grafana
resource "aws_security_group_rule" "grafana_alb_access" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.grafana_alb_sg.id
  security_group_id        = aws_security_group.monitoring_sg.id
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

# ALB for Grafana
resource "aws_lb" "grafana" {
  name               = "grafana-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb_sg.id]
  subnets            = [aws_subnet.shared_public_1.id, aws_subnet.shared_public_2.id]

  enable_deletion_protection = false

  tags = {
    Name = "grafana-alb"
  }
}

# ALB Target Group for Frontend
resource "aws_lb_target_group" "frontend" {
  name        = "frontend-target-group"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.production.id
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

# Target Group for Grafana
resource "aws_lb_target_group" "grafana" {
  name        = "grafana-target-group"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.shared_services.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/login"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "grafana-target-group"
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

# ALB Listener for Grafana
resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  tags = {
    Name = "grafana-listener"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "main-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "main-ecs-cluster"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition for Frontend
resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = "nginx:alpine"
      essential = true
      command   = ["sh", "-c", "sed -i 's/80/8080/g' /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
      portMappings = [
        {
          containerPort = 8080
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/frontend"
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "frontend-task-definition"
  }
}

# ECS Task Definition for PostgreSQL
resource "aws_ecs_task_definition" "postgres" {
  family                   = "postgres-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "postgres"
      image     = "postgres:15-alpine"
      essential = true
      portMappings = [
        {
          containerPort = 5432
        }
      ]
      environment = [
        {
          name  = "POSTGRES_DB"
          value = "appdb"
        },
        {
          name  = "POSTGRES_USER"
          value = "dbadmin"
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = "password123"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/postgres"
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "postgres-task-definition"
  }
}

# ECS Task Definition for Prometheus
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "prometheus-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = "prom/prometheus:latest"
      essential = true
      portMappings = [
        {
          containerPort = 9090
        }
      ]
      command = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus/",
        "--web.console.libraries=/etc/prometheus/console_libraries",
        "--web.console.templates=/etc/prometheus/consoles",
        "--storage.tsdb.retention.time=200h",
        "--web.enable-lifecycle"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/prometheus"
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "prometheus-task-definition"
  }
}

# ECS Task Definition for Grafana
resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "grafana/grafana:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
        }
      ]
      environment = [
        {
          name  = "GF_SECURITY_ADMIN_PASSWORD"
          value = "admin123"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/grafana"
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "grafana-task-definition"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ecs_frontend" {
  name              = "/ecs/frontend"
  retention_in_days = 30

  tags = {
    Name = "ecs-frontend-logs"
  }
}

resource "aws_cloudwatch_log_group" "ecs_postgres" {
  name              = "/ecs/postgres"
  retention_in_days = 30

  tags = {
    Name = "ecs-postgres-logs"
  }
}

resource "aws_cloudwatch_log_group" "ecs_prometheus" {
  name              = "/ecs/prometheus"
  retention_in_days = 30

  tags = {
    Name = "ecs-prometheus-logs"
  }
}

resource "aws_cloudwatch_log_group" "ecs_grafana" {
  name              = "/ecs/grafana"
  retention_in_days = 30

  tags = {
    Name = "ecs-grafana-logs"
  }
}

# ECS Service for Frontend
resource "aws_ecs_service" "frontend" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_app_1.id]
    security_groups  = [aws_security_group.ecs_frontend_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.frontend]

  tags = {
    Name = "frontend-ecs-service"
  }
}

# ECS Service for PostgreSQL
resource "aws_ecs_service" "postgres" {
  name            = "postgres-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_db_1.id]
    security_groups  = [aws_security_group.postgres_sg.id]
    assign_public_ip = false
  }

  tags = {
    Name = "postgres-ecs-service"
  }
}

# ECS Service for Prometheus
resource "aws_ecs_service" "prometheus" {
  name            = "prometheus-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.shared_private_1.id]
    security_groups  = [aws_security_group.monitoring_sg.id]
    assign_public_ip = false
  }

  tags = {
    Name = "prometheus-ecs-service"
  }
}

# ECS Service for Grafana
resource "aws_ecs_service" "grafana" {
  name            = "grafana-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.shared_private_1.id]
    security_groups  = [aws_security_group.monitoring_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.grafana]

  tags = {
    Name = "grafana-ecs-service"
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

  tags = {
    Name = "private-route-table"
  }
}

# Separate route resources for private route table
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route" "private_tgw_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
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
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.shared.id
  }

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

resource "aws_route_table_association" "shared_public_2_association" {
  subnet_id      = aws_subnet.shared_public_2.id
  route_table_id = aws_route_table.shared_public_rt.id
}

resource "aws_route_table_association" "shared_private_1_association" {
  subnet_id      = aws_subnet.shared_private_1.id
  route_table_id = aws_route_table.shared_private_rt.id
}