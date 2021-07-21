# Declare Provider Requirements
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  required_version = ">= 0.14.9"
}

# Configure AWS Provider
provider "aws" {
  region     = "us-east-1"
  access_key = "ACCESS-KEY"
  secret_key = "SECRET-KEY"
}

# Initialize a bucket in s3 for the backend state store
resource "aws_s3_bucket" "pgc-s3bucket" {
  bucket = "pgc-s3bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = {
    Name  = "pgc-s3bucket"
    Group = var.group_tag
  }
}

# Create VPC
resource "aws_vpc" "pgc-vpc" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  tags = {
    Name  = "pgc-vpc"
    Group = var.group_tag
  }
}

# Create Public Subnets
resource "aws_subnet" "pgc-subnet-public" {
  count                   = length(var.cidr_public_subnet)
  vpc_id                  = aws_vpc.pgc-vpc.id
  cidr_block              = var.cidr_public_subnet[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name  = format("pgc-subnet-public%d", (count.index + 1))
    Group = var.group_tag
  }
}

# Create Private Subnets
resource "aws_subnet" "pgc-subnet-private" {
  count             = length(var.cidr_private_subnet)
  vpc_id            = aws_vpc.pgc-vpc.id
  cidr_block        = var.cidr_private_subnet[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name  = format("pgc-subnet-private%d", (count.index + 1))
    Group = var.group_tag
  }
}

# Create Elastic IP
resource "aws_eip" "pgc-eip" {
  vpc = true
  tags = {
    Name  = "pgc-eip"
    Group = var.group_tag
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "pgc-igw" {
  vpc_id = aws_vpc.pgc-vpc.id
  tags = {
    Name  = "pgc-igw"
    Group = var.group_tag
  }
}

# Create NAT Gateway
resource "aws_nat_gateway" "pgc-nat" {
  allocation_id = aws_eip.pgc-eip.id
  subnet_id     = element(aws_subnet.pgc-subnet-public.*.id, 0)
  tags = {
    Name  = "pgc-nat"
    Group = var.group_tag
  }
}

# Create Routing Table for Public Subnet
resource "aws_route_table" "pgc-public-rtb" {
  vpc_id = aws_vpc.pgc-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pgc-igw.id
  }
  tags = {
    Name  = "pgc-public-rtb"
    Group = var.group_tag
  }
}

# Associate Routing Table to Public Subnet
resource "aws_route_table_association" "pgc-public-rtb-assn" {
  count          = length(var.cidr_public_subnet)
  subnet_id      = element(aws_subnet.pgc-subnet-public.*.id, count.index)
  route_table_id = aws_route_table.pgc-public-rtb.id
}

# Create Routing Table for Private Subnet
resource "aws_route_table" "pgc-rtb-nat" {
  vpc_id = aws_vpc.pgc-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.pgc-nat.id
  }
  tags = {
    Name  = "pgc-rtb-nat"
    Group = var.group_tag
  }
}

# Associate Routing Table to Private Subnet
resource "aws_route_table_association" "pgc-nat-rtb-assn" {
  count          = length(var.cidr_private_subnet)
  subnet_id      = element(aws_subnet.pgc-subnet-private.*.id, count.index)
  route_table_id = aws_route_table.pgc-rtb-nat.id
}

# Create Security Group for Bastion Host
resource "aws_security_group" "pgc-bastion-sg" {
  name   = "pgc-bastion-sg"
  vpc_id = aws_vpc.pgc-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.MyIP.body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "pgc-bastion-sg"
    Group = var.group_tag
  }
}

# Create Security Group for Remote Host
resource "aws_security_group" "pgc-remote-sg" {
  name   = "pgc-remote-sg"
  vpc_id = aws_vpc.pgc-vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.pgc-bastion-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "pgc-remote-sg"
    Group = var.group_tag
  }
}

# Create Security Group for Private Instance
resource "aws_security_group" "pgc-private-sg" {
  name   = "pgc-private-sg"
  vpc_id = aws_vpc.pgc-vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_vpc]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "pgc-private-sg"
    Group = var.group_tag
  }
}

# Create Security Group for Public Instance
resource "aws_security_group" "pgc-public-sg" {
  name   = "pgc-public-sg"
  vpc_id = aws_vpc.pgc-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.MyIP.body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "pgc-public-sg"
    Group = var.group_tag
  }
}

# Create EC2 Key Pair
resource "aws_key_pair" "pgc-key" {
  key_name   = "publicKey"
  public_key = file(var.public_key_path)
}

# Create Bastion Host
resource "aws_instance" "bastion" {
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  subnet_id              = element(aws_subnet.pgc-subnet-public.*.id, 0)
  key_name               = aws_key_pair.pgc-key.key_name
  vpc_security_group_ids = [aws_security_group.pgc-bastion-sg.id]
  tags = {
    Name  = "bastion"
    Group = var.group_tag
  }
}

# Create Jenkins Host
resource "aws_instance" "jenkins" {
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  subnet_id              = element(aws_subnet.pgc-subnet-private.*.id, 0)
  key_name               = aws_key_pair.pgc-key.key_name
  vpc_security_group_ids = [aws_security_group.pgc-remote-sg.id]
  tags = {
    Name  = "jenkins"
    Group = var.group_tag
  }
}

# Create App Host
resource "aws_instance" "app" {
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  subnet_id              = element(aws_subnet.pgc-subnet-private.*.id, 0)
  key_name               = aws_key_pair.pgc-key.key_name
  vpc_security_group_ids = [aws_security_group.pgc-remote-sg.id]
  tags = {
    Name  = "app"
    Group = var.group_tag
  }
}

# Variables
variable "cidr_vpc" {
  description = "CIDR Block for the VPC"
  default     = "10.0.0.0/16"
}
variable "cidr_public_subnet" {
  description = "CIDR Block for Public Subnets"
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
  type        = list(string)
}
variable "cidr_private_subnet" {
  description = "CIDR Block for Private Subnets"
  default     = ["10.0.30.0/24", "10.0.40.0/24"]
  type        = list(string)
}
variable "availability_zones" {
  description = "Availability Zone in US East (N. Virginia)"
  default     = ["us-east-1a", "us-east-1b"]
  type        = list(string)
}
variable "instance_ami" {
  description = "AMI (Ubuntu Server 20.04 LTS) for aws EC2 instance"
  default     = "ami-09e67e426f25ce0d7"
}
variable "instance_type" {
  description = "Instance Type to meet our computing needs"
  default     = "t2.micro"
}
variable "public_key_path" {
  description = "Public key path"
  default     = "~/.ssh/id_rsa.pub"
}
variable "group_tag" {
  description = "Default grouping for all the Resources"
  default     = "pgc-course4"
}

# Public API to get the self-IP
data "http" "MyIP" {
  url = "http://ipv4.icanhazip.com"
}
