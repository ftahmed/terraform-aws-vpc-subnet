/*==== The VPC ======*/
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project}-vpc"
    Environment = "${var.environment}"
  }
}

/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.project}-igw"
    Environment = "${var.environment}"
  }
}

/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}

/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  depends_on    = [aws_internet_gateway.ig]

  tags = {
    Name        = "${var.project}-nat"
    Environment = "${var.environment}"
  }
}

/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-public-${element(var.availability_zones, count.index)}"
    Environment = "${var.environment}"
  }
}

/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project}-private-${element(var.availability_zones, count.index)}"
    Environment = "${var.environment}"
  }
}

/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.project}-private-route-table"
    Environment = "${var.environment}"
  }
}

/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.project}-public-route-table"
    Environment = "${var.environment}"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

/* Route table associations */
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

/*==== VPC's Default Security Group ======*/
resource "aws_security_group" "default" {
  name        = "${var.project}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]

  /* Allow only ssh traffic from internet */
  ingress {
    from_port = "22"
    to_port   = "22"
    protocol  = "TCP"
    self      = true
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  /* Allow all outbound traffic to internet */
  egress {
    from_port        = "0"
    to_port          = "0"
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Environment = "${var.environment}"
  }
}

/*==== Bastion host ======*/
resource "aws_instance" "bastion" {
  ami = data.aws_ami_ids.centos7.ids[0]
  associate_public_ip_address = true
  instance_type = "t3a.nano"
  subnet_id = aws_subnet.public_subnet[0].id
  vpc_security_group_ids = ["${aws_security_group.bastion.id}"]
  key_name = aws_key_pair.main.key_name

  tags = {
    Name = "${var.project}-bastion"
  }
}

data "aws_ami_ids" "centos7" {
  owners = ["aws-marketplace"]

  filter {
    name   = "product-code"
    values = ["cvugziknvmxgqna9noibqnnsy"]
  }
  filter {
    name   = "name"
    values = ["CentOS-7-*x86_64-*"]
  }
}

resource "aws_eip" "bastion" {
  vpc        = true
  instance   = aws_instance.bastion.id
  depends_on = [aws_internet_gateway.ig]
}

resource "aws_security_group" "bastion" {
  name = "${var.project}-bastion"
  description = "Security group for the bastion server"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project}-bastion-sg"
  }
}

resource "aws_security_group_rule" "ssh-bastion-world" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  # Please restrict your ingress to only necessary IPs and ports.
  # Opening to 0.0.0.0/0 can lead to security vulnerabilities
  # You may want to set a fixed ip address if you have a static ip
  security_group_id = aws_security_group.bastion.id
  cidr_blocks = ["0.0.0.0/0"]
}

// tanvir-key-pair-467952971505.rsa.pub
resource "aws_key_pair" "main" {
  key_name = "${var.project}-tanvir-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDgoYgZrq/LuyTD/NTq1tVorS90Gy+k4dTyczj8d422nAGoeAOUVyUEfxnyX061sgqCIPJaX0rWd85ukLUKWW8qN84rpyD9Lb/JUmlwDPlMFS5zBNXwIzyHZuvMxP1Xq2yhXTWHKJk03dqDyNAPBvYGxrvxbfQhE8zc1VQKnascuYJcZIdTXBn4jRqtjF0lc5hg7qFx1EQv5bLNXmCiGkgHurj3imTa6Qb2mbOrYviWy75pBllWFgNNuh3z2/VttDnTHqAW3bfsH5wm6gIWWqP7va+7RBA1B+hotI3/nmHR5rqXhTVmn1ecfQ0jYaN53X9RAz/naIeqEp/8bNZuQPQd"
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
