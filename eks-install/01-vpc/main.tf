# -----------------------------------------------------------------------------
# Stack: 01-vpc
# Networking for EKS: VPC, public/private subnets, IGW, NAT, routes, S3 endpoint.
# Apply after 00-s3. Then apply 02-eks.
# -----------------------------------------------------------------------------

# Pin Terraform and the AWS provider so applies stay compatible across machines.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state: S3 holds this stack's state; DynamoDB prevents concurrent applies.
  backend "s3" {
    bucket         = "terraform-eks-state-s3-bucket-u17tc1"
    key            = "01-vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-eks-state-locks"
    encrypt        = true
  }
}

# Default AWS provider. Region comes from var.region.
provider "aws" {
  region = var.region
}

# Cluster VPC. DNS hostnames and DNS support are required by EKS
# (nodes and the API resolve AWS service names through Amazon DNS).
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private subnets for worker nodes and control-plane ENIs.
# internal-elb = 1 tells the load balancer controller to place internal LBs here.
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                        = "${var.cluster_name}-private-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# Public subnets for NAT gateways and internet-facing load balancers (role/elb = 1).
# map_public_ip_on_launch is off: nodes run in private subnets. ALB ENIs still get
# public IPs because the Ingress uses scheme = internet-facing.
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Internet gateway so public subnets can reach the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Elastic IPs for the NAT gateways (one per public subnet / AZ).
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-${count.index + 1}"
  }

  # NAT EIPs need the IGW to exist on the VPC.
  depends_on = [aws_internet_gateway.main]
}

# NAT gateway in each public subnet so private-subnet nodes can pull images and packages.
resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${count.index + 1}"
  }

  # A NAT gateway cannot be created until the VPC has an internet gateway.
  depends_on = [aws_internet_gateway.main]
}

# Public route table: default route (0.0.0.0/0) goes to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public"
  }
}

# One private route table per AZ: default route goes to that AZ's NAT gateway.
# Keeping NAT local to the AZ avoids cross-AZ data charges on egress.
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.cluster_name}-private-${count.index + 1}"
  }
}

# Attach each private subnet to its AZ-specific private route table.
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Attach all public subnets to the shared public route table.
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Gateway endpoint for S3 (no hourly cost). ECR image layers live in S3, so this
# keeps those pulls on the AWS network instead of hairpinning through NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${var.cluster_name}-s3"
  }
}
