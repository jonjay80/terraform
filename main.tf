terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.51.0"
    }
  }
  backend "s3" {
    bucket = "jjay-tf-98277"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = var.default_tags
  }
}

# create VPC; CIDR 10.0.0.0/16
resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true
  tags = {
    "Name" = "${var.default_tags.env}-VPC"
  }

}
# public subnets 10.0.0.0/24
resource "aws_subnet" "public" {
  count                   = var.public_subnet_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  tags = {
    "Name" = "${var.default_tags.env}-Public-Subnet-${data.aws_availability_zones.availability_zone.names[count.index]}"
  }
  availability_zone = data.aws_availability_zones.availability_zone.names[count.index]
}
# private subnets
resource "aws_subnet" "private" {
  count      = var.private_subnet_count
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + var.public_subnet_count)
  tags = {
    "Name" = "${var.default_tags.env}-Private-Subnet-${data.aws_availability_zones.availability_zone.names[count.index]}"
  }
  availability_zone = data.aws_availability_zones.availability_zone.names[count.index]
}
# IGW
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.default_tags.env}-IGW"
  }
}
# NGW
resource "aws_nat_gateway" "main_nat" {
  allocation_id = aws_eip.NAT_EIP.id
  subnet_id     = aws_subnet.public.0.id
  tags = {
    "Name" = "${var.default_tags.env}-NGW"
  }
}
# EIP
resource "aws_eip" "NAT_EIP" {
  vpc = true
}
# default route table
resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  tags = {
    "Name" = "${var.default_tags.env}-Default-RT"
  }
}
# default route table association
resource "aws_main_route_table_association" "default" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_default_route_table.default.id
}
# public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.default_tags.env}-Public-RT"
  }
}
# public route
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_igw.id
}
# public route table association
resource "aws_route_table_association" "public" {
  count          = var.public_subnet_count
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.default_tags.env}-Private-RT"
  }
}
# private route
resource "aws_route" "private" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.main_nat.id
}
# private route table association
resource "aws_route_table_association" "private" {
  count          = var.private_subnet_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private.id
}
