terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Find latest Ubuntu 22.04 (Jammy) official AMI from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "random_pet" "suffix" {
  length = 2
}

# S3 bucket for frontend zip (private)
resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = lower(format("%s-%s-%s", var.bucket_name_prefix, random_pet.suffix.id, var.aws_region))
  acl           = "private"
  force_destroy = true # removes objects when bucket is destroyed (useful for tear down)
  tags = {
    Name = "react-frontend-bucket"
    Env  = "dev"
  }
}

# Upload local frontend.zip (ensure frontend.zip is in the module directory)
resource "aws_s3_bucket_object" "frontend_zip" {
  bucket = aws_s3_bucket.frontend_bucket.id
  key    = "frontend.zip"
  source = "${path.module}/frontend.zip"
  etag   = filemd5("${path.module}/frontend.zip")
}

# IAM role/profile for EC2 to read S3
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "ec2-s3-read-role-${random_pet.suffix.id}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "s3_read_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.frontend_bucket.arn,
      "${aws_s3_bucket.frontend_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name   = "ec2-s3-read-policy-${random_pet.suffix.id}"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.s3_read_policy.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile-${random_pet.suffix.id}"
  role = aws_iam_role.ec2_role.name
}

# Security group allowing HTTP and SSH
resource "aws_security_group" "react_sg" {
  name        = "react-sg-${random_pet.suffix.id}"
  description = "Allow HTTP and SSH"
  vpc_id      = null # default uses EC2-Classic or default VPC depending on your account

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

  tags = {
    Name = "react-sg"
  }
}

# EC2 instance
resource "aws_instance" "react_app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.react_sg.id]
  associate_public_ip_address = true
  tags = {
    Name = "react-ec2-instance"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    echo "[userdata] updating packages"
    apt-get update -y

    echo "[userdata] install base packages"
    apt-get install -y nginx unzip curl awscli

    echo "[userdata] install Node.js 18"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs build-essential

    echo "[userdata] create workspace"
    mkdir -p /tmp/frontend

    echo "[userdata] download frontend from S3"
    aws s3 cp s3://${aws_s3_bucket.frontend_bucket.bucket}/${aws_s3_bucket_object.frontend_zip.key} /tmp/frontend.zip --region ${var.aws_region}

    echo "[userdata] unzip"
    unzip -o /tmp/frontend.zip -d /tmp/frontend || true

    # If package.json exists -> build; else use build/ or index.html directly
    if [ -f /tmp/frontend/package.json ]; then
      cd /tmp/frontend
      echo "[userdata] package.json found, running npm ci & build"
      npm ci --silent || npm install --silent
      npm run build --silent || true
      SRC_DIR="/tmp/frontend/build"
    elif [ -d /tmp/frontend/build ]; then
      SRC_DIR="/tmp/frontend/build"
    elif [ -f /tmp/frontend/index.html ]; then
      SRC_DIR="/tmp/frontend"
    else
      echo "[userdata] No build found and no package.json; exiting" > /var/log/user-data.log
      exit 1
    fi

    echo "[userdata] deploying files to nginx html root"
    rm -rf /var/www/html/*
    cp -r ${SRC_DIR}/* /var/www/html/
    chown -R www-data:www-data /var/www/html

    systemctl enable nginx
    systemctl restart nginx
    echo "[userdata] finished"
  EOF
}

# Elastic IP (optional but gives stable public IP)
resource "aws_eip" "react_eip" {
  instance = aws_instance.react_app.id
  vpc      = true
}
