terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.56"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_security_group" "devsecops_sg" {
  name        = "${var.project_name}-sg"
  description = "DevSecOps security group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DefectDojo"
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SonarQube"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

resource "aws_key_pair" "devsecops" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key
  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

resource "aws_eip" "devsecops" {
  domain = "vpc"
  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }
}

resource "aws_instance" "devsecops" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  key_name               = aws_key_pair.devsecops.key_name
  vpc_security_group_ids = [aws_security_group.devsecops_sg.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    tags = {
      Name    = "${var.project_name}-root"
      Project = var.project_name
    }
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    repo_url          = var.repo_url
    dd_secret_key     = var.dd_secret_key
    dd_admin_password = var.dd_admin_password
    dd_db_user        = var.dd_db_user
    dd_db_password    = var.dd_db_password
    sonar_db_user     = var.sonar_db_user
    sonar_db_password = var.sonar_db_password
    public_ip         = aws_eip.devsecops.public_ip
  })

  user_data_replace_on_change = true

  tags = {
    Name    = "${var.project_name}-instance"
    Project = var.project_name
  }
}

resource "aws_eip_association" "devsecops" {
  instance_id   = aws_instance.devsecops.id
  allocation_id = aws_eip.devsecops.id
}
