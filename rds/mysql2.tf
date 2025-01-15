# Define variables
variable "db_password" {
  description = "Password for the RDS instance"
  type        = string
  sensitive   = true  # This ensures the password won't be shown in logs
}

variable "environment" {
  description = "Environment (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

# VPC Data Sources
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["main"]  # Replace with your VPC name
  }
}

# Get the existing Internet Gateway
data "aws_internet_gateway" "main" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# Create Public Subnets (minimum 2 required for RDS)
resource "aws_subnet" "subnet_1" {
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Subnet 1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Subnet 2"
  }
}

# Create DB Subnet Group
resource "aws_db_subnet_group" "rds-subnet-group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  tags = {
    Name = "DB subnet group"
  }
}

# Create Security Group for RDS
data "aws_security_group" "rds" {
  name        = "rds-security-group"
  vpc_id      = data.aws_vpc.existing.id
}

# Create RDS Instance
resource "aws_db_instance" "mysql" {
  identifier           = "mysql"
  engine              = "mysql"
  engine_version      = "8.4.3"
  instance_class      = "db.t3.micro"  # Change this based on your needs
  allocated_storage   = 20
  storage_type        = "gp2"
  
  # Database settings
  db_name             = "box_storage"
  username            = "root"
  password            = var.db_password
  
  # Network settings
  db_subnet_group_name   = aws_db_subnet_group.rds-subnet-group.name
  vpc_security_group_ids = [data.aws_security_group.rds.id]
  publicly_accessible    = true  # Set to false for production

  # Backup settings
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  # Enhanced monitoring
  monitoring_interval = 0  # Set to 60 for production
  
  # Other settings
  auto_minor_version_upgrade = true
  deletion_protection       = false  # Set to true for production
  skip_final_snapshot      = true   # Set to false for production

  tags = {
    Name = "MySQL RDS Instance"
  }
}

# Output the endpoint
output "rds_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  value = aws_db_instance.mysql.port
}

# Create a null_resource to handle the MySQL initialization
resource "null_resource" "db_setup" {
  depends_on = [aws_db_instance.mysql]

  provisioner "local-exec" {
    command = <<-EOT
      mysql -h ${aws_db_instance.mysql.endpoint} -P ${aws_db_instance.mysql.port} -u ${aws_db_instance.mysql.username} -p${var.db_password} <<EOF
      
      -- Create box table
      CREATE TABLE IF NOT EXISTS box (
        id INT AUTO_INCREMENT PRIMARY KEY,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        name VARCHAR(255),
        owner VARCHAR(255)
      );

      -- Create items table with foreign key relationship
      CREATE TABLE IF NOT EXISTS items (
        id INT AUTO_INCREMENT PRIMARY KEY,
        box_id INT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        name VARCHAR(255),
        description TEXT,
        FOREIGN KEY (box_id) REFERENCES box(id)
      );

      -- Insert sample data
      INSERT INTO box (name, owner) VALUES 
        ('First Box', 'John Doe'),
        ('Storage Box', 'Jane Smith'),
        ('Tool Box', 'Bob Wilson');

      INSERT INTO items (box_id, name, description) VALUES 
        (1, 'Item 1', 'First item in box 1'),
        (1, 'Item 2', 'Second item in box 1'),
        (2, 'Item 3', 'First item in box 2');
      EOF
    EOT
  }
}