# Variables
variable "db_username" {
  description = "Database administrator username"
  type        = string
  default     = "wordpress"
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

# VPC Data Sources
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["main"]  # Replace with your VPC name
  }
}

# Get the Internet Gateway associated with your VPC
data "aws_internet_gateway" "main" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# Create a route table for your public subnets
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.existing.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.main.id
  }
  tags = {
    Name = "public-route-table"
  }
}

# Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = data.aws_vpc.existing.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true    # Added this line
  
  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = data.aws_vpc.existing.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true    # Added this line
  
  tags = {
    Name = "public-subnet-2"
  }
}

# Route table associations
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group for WordPress
resource "aws_security_group" "wordpress" {
  name        = "wordpress"
  description = "Security group for WordPress containers"
  vpc_id      = data.aws_vpc.existing.id
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
}

# Create RDS Security Group
resource "aws_security_group" "rds" {
  name        = "wordpress-rds"
  description = "Security group for WordPress RDS instance"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  db_name             = "wordpress"
  username            = var.db_username
  password            = var.db_password
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name

  backup_retention_period = 7
  multi_az               = false
}

# ECS Cluster
resource "aws_ecs_cluster" "wordpress" {
  name = "wordpress-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = "256"
  memory                  = "512"
  container_definitions = jsonencode([
    {
      name  = "wordpress"
      image = "public.ecr.aws/docker/library/wordpress:latest"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = aws_db_instance.wordpress.endpoint
        },
        {
          name  = "WORDPRESS_DB_USER"
          value = var.db_username
        },
        {
          name  = "WORDPRESS_DB_PASSWORD"
          value = var.db_password
        },
        {
          name  = "WORDPRESS_DB_NAME"
          value = "wordpress"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "wordpress" {
  name            = "wordpress-service"
  cluster         = aws_ecs_cluster.wordpress.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.wordpress.id]
    assign_public_ip = true
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}