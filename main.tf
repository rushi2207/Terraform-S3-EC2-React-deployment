provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "react_app" {
  ami           = "ami-08c40ec9ead489470" # Ubuntu 22.04
  instance_type = "t2.micro"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.react_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    echo "===== USER DATA STARTED ====="

    # Update & install basics
    apt-get update -y
    apt-get install -y curl git nginx

    # Install Node.js LTS
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs build-essential

    # Clone repo
    rm -rf /home/ubuntu/reactapp
    git clone ${var.github_repo} /home/ubuntu/reactapp
    cd /home/ubuntu/reactapp

    # Build react app
    npm install
    npm run build

    # Copy build files to nginx root
    rm -rf /var/www/html/*
    cp -r build/* /var/www/html/

    # Fix permissions
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html

    # Restart nginx
    sleep 5
    systemctl enable nginx
    systemctl restart nginx

    echo "===== USER DATA FINISHED ====="
  EOF

  tags = {
    Name = "react-app-server"
  }
}

resource "aws_security_group" "react_sg" {
  name        = "react-sg"
  description = "Allow HTTP and SSH"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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
