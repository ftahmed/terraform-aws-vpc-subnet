# bastion
resource "aws_instance" "bastion" {
  ami = data.aws_ami_ids.centos7.id
  associate_public_ip_address = true
  instance_type = "t3a.nano"
  subnet_id = aws_subnet.eo-public-eu-west-2a.id
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

resource "aws_security_group" "bastion" {
  name = "${var.project}-bastion"
  description = "Security group for the bastion server"
  vpc_id = module.networking.aws_vpc.vpc.id

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

resource "aws_key_pair" "main" {
  key_name = "${var.project}-key"
  public_key = "ssh-rsa something"
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
