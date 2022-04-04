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

resource "aws_vpc_dhcp_options" "dns_resolver" {
  domain_name         = "metafour.cloud"
  domain_name_servers = ["AmazonProvidedDNS"]
}

resource "aws_vpc_dhcp_options_association" "dns_resolver" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.dns_resolver.id
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

/*==== Data sources: AMIs ======*/
// https://aws.amazon.com/marketplace/pp/prodview-foff247vr2zfw
// https://wiki.centos.org/Cloud/AWS
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

// https://aws.amazon.com/marketplace/pp/prodview-nejgiy45fvv4m
data "aws_ami_ids" "virtuozzo7" {
  owners = ["aws-marketplace"]

  filter {
    name   = "product-code"
    values = ["8ksrxjo08vh1tkcw170zt1p2e"]
  }
  filter {
    name   = "name"
    values = ["Virtuozzo 7*"]
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

resource "aws_eip" "bastion" {
  vpc        = true
  instance   = aws_instance.bastion.id
  depends_on = [aws_internet_gateway.ig]
}

resource "aws_security_group" "bastion" {
  name = "${var.project}-bastion-sg"
  description = "Security group for the bastion server"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project}-bastion"
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

resource "aws_security_group_rule" "ssh-bastion-alb" {
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  security_group_id = aws_security_group.bastion.id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "ssh-bastion-webapp" {
  type = "egress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  security_group_id = aws_security_group.bastion.id
  cidr_blocks = ["10.0.0.0/16"]
}

// tanvir-key-pair-467952971505.rsa.pub
resource "aws_key_pair" "main" {
  key_name = "${var.project}-tanvir-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDgoYgZrq/LuyTD/NTq1tVorS90Gy+k4dTyczj8d422nAGoeAOUVyUEfxnyX061sgqCIPJaX0rWd85ukLUKWW8qN84rpyD9Lb/JUmlwDPlMFS5zBNXwIzyHZuvMxP1Xq2yhXTWHKJk03dqDyNAPBvYGxrvxbfQhE8zc1VQKnascuYJcZIdTXBn4jRqtjF0lc5hg7qFx1EQv5bLNXmCiGkgHurj3imTa6Qb2mbOrYviWy75pBllWFgNNuh3z2/VttDnTHqAW3bfsH5wm6gIWWqP7va+7RBA1B+hotI3/nmHR5rqXhTVmn1ecfQ0jYaN53X9RAz/naIeqEp/8bNZuQPQd"
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

/*==== Application and web server ======*/
resource "aws_instance" "webapp" {
  ami = data.aws_ami_ids.virtuozzo7.ids[0]
  instance_type = "m5.large"
  subnet_id = aws_subnet.private_subnet[0].id
  vpc_security_group_ids = [aws_security_group.default.id, "${aws_security_group.webapp.id}"]
  key_name = aws_key_pair.main.key_name

  tags = {
    Name = "${var.project}-webapp"
  }
}

resource "aws_security_group" "webapp" {
  name = "${var.project}-webapp-sg"
  description = "For Web and app servers"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project}-webapp"
  }
}

resource "aws_security_group_rule" "ssh-webapp-bastion" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  security_group_id = aws_security_group.webapp.id
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "https-webapp-bastion" {
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  security_group_id = aws_security_group.webapp.id
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "pgsql-webapp-pgdb" {
  type = "egress"
  from_port = 5432
  to_port = 5432
  protocol = "tcp"
  security_group_id = aws_security_group.webapp.id
  source_security_group_id = aws_security_group.pgdb.id
}

/*==== Database server (primary) ======*/
resource "aws_instance" "pgdb" {
  ami = data.aws_ami_ids.centos7.ids[0]
  instance_type = "m5.large"
  subnet_id = aws_subnet.private_subnet[0].id
  vpc_security_group_ids = ["${aws_security_group.pgdb.id}"]
  key_name = aws_key_pair.main.key_name

  tags = {
    Name = "${var.project}-pgdb"
  }
}

resource "aws_security_group" "pgdb" {
  name = "${var.project}-pgdb-sg"
  description = "For Database servers"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project}-pgdb"
  }
}

resource "aws_security_group_rule" "ssh-pgdb-bastion" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  security_group_id = aws_security_group.pgdb.id
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "pgsql-pgdb-webapp" {
  type = "ingress"
  from_port = 5432
  to_port = 5432
  protocol = "tcp"
  security_group_id = aws_security_group.pgdb.id
  source_security_group_id = aws_security_group.webapp.id
}


/*==== Application load balancer ====*/
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project}-alb-logs"

  tags = {
    Name        = "${var.project}-alb-logs"
    Environment = "${var.environment}"
  }
}

resource "aws_s3_bucket_acl" "alb_logs_acl" {
  bucket = aws_s3_bucket.alb_logs.id
  //acl    = "private"
  acl    = "log-delivery-write"
}

resource "aws_security_group" "alb" {
  name = "${var.project}-alb-sg"
  description = "For Application load balancer"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project}-alb"
  }
}

resource "aws_security_group_rule" "http-alb-world" {
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "tcp"
  security_group_id = aws_security_group.alb.id
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "https-alb-world" {
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  security_group_id = aws_security_group.alb.id
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "https-alb-bastion" {
  type = "egress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  security_group_id = aws_security_group.alb.id
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_alb" "alb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]

  enable_deletion_protection = true

  /*access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "${var.project}-alb"
    enabled = true
  }*/

  tags = {
    Name = "${var.project}-alb"
    Environment = "${var.environment}"
  }
}

resource "aws_alb_listener" "alb_listener_http" {
  load_balancer_arn = aws_alb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "alb_listener_https" {
  load_balancer_arn = aws_alb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:eu-west-2:467952971505:certificate/946deaf2-fb05-46e8-aee1-727e7ac8302a"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.alb_target_group_https.arn
  }
}

resource "aws_alb_target_group" "alb_target_group_https" {
  name     = "alb-tg-https"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.vpc.id
}

resource "aws_alb_target_group_attachment" "alb-tg-https-bastion" {
  target_group_arn = aws_alb_target_group.alb_target_group_https.arn
  target_id        = aws_instance.bastion.id
  port             = 443
}
