terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}



provider "aws" {
  region  = "us-east-1"
}

resource "aws_instance" "web2" {
  ami           = "ami-0e2c8caa4b6378d8c"  # Ubuntu 24.04 LTS
  instance_type = "t2.micro"
  key_name      = "Key"  # SSH key name

  tags = {
    Name = "web2"
  }

  # Reference the security group by its name
  security_groups = [aws_security_group.nginx_security_group.name]

  # User data script to install Nginx on the instance
  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y nginx
              echo "<!DOCTYPE html>
              <html lang="en">
              <head>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>Hello World</title>
              </head>
              <body>
                  <h1>Hello, World!</h1>
                  <p>Welcome to your Nginx server!</p>
              </body>
              </html>" | sudo tee /var/www/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF

  # Enable monitoring
  monitoring = true

  # Enable public IP assignment
  associate_public_ip_address = true
}

resource "aws_security_group" "nginx_security_group" {
  name_prefix = "nginx-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allows SSH access from any IP
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allows HTTP access from any IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
}

output "instance_public_ip" {
  value = aws_instance.web2.public_ip
}
