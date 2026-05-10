provider "aws" {
  region  = var.region
  profile = "seifuser"
}

# ---------------- AWS KEY PAIR ----------------
resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = file("ansible/my-keypair.pub")
}

# ---------------- VPC ----------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "my-vpc"
  }
}

# ---------------- INTERNET GATEWAY ----------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# ---------------- PUBLIC SUBNETS ----------------
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_1
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_2
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
}

# ---------------- PRIVATE SUBNETS ----------------
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_1
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_2
  availability_zone = "us-east-1b"
}

# ---------------- PUBLIC ROUTE TABLE ----------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# ---------------- NAT GATEWAY ----------------
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [aws_internet_gateway.igw]
}

# ---------------- PRIVATE ROUTE TABLE ----------------
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}

# =====================================================
# SECURITY GROUPS
# =====================================================

# ---------------- BASTION SG ----------------
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- ALB SG ----------------
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# ---------------- APP SG ----------------
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- IAM ROLE ----------------
resource "aws_iam_role" "ec22_role" {
  name = "ec22-s33-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "s3_logs_policy" {
  name = "ec2-s3-logs-write-only"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "s3:PutObject",
      Resource = "${aws_s3_bucket.alb_logs.arn}/logs/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec22_role.name
  policy_arn = aws_iam_policy.s3_logs_policy.arn
}

resource "aws_iam_instance_profile" "profile" {
  role = aws_iam_role.ec22_role.name
}

# ---------------- S3 ----------------
resource "aws_s3_bucket" "alb_logs" {
  bucket = var.alb_logs_bucket
}

resource "aws_s3_bucket_versioning" "alb_logs_versioning" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "alb_logs_policy" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "logdelivery.elasticloadbalancing.amazonaws.com"
      },
      Action   = "s3:PutObject",
      Resource = "${aws_s3_bucket.alb_logs.arn}/*"
    }]
  })
}

# ---------------- ALB ----------------
resource "aws_lb" "alb" {
  name               = "devops-alb"
  load_balancer_type = "application"

  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  security_groups = [aws_security_group.alb_sg.id]

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    enabled = true
  }
}

# ---------------- TARGET GROUP ----------------
resource "aws_lb_target_group" "tg" {
  name     = "devops-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

# ---------------- LAUNCH TEMPLATE ----------------
resource "aws_launch_template" "lt" {
  name_prefix   = "app-lt"
  image_id      = var.ami
  instance_type = var.instance_type

  key_name = aws_key_pair.generated_key.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app_sg.id]
  }
}

# ---------------- AUTO SCALING GROUP ----------------
resource "aws_autoscaling_group" "asg" {
  desired_capacity = 2
  min_size         = 2
  max_size         = 4

  vpc_zone_identifier = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  target_group_arns = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 60
}

# ---------------- LISTENER ----------------
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ---------------- BASTION ----------------
resource "aws_instance" "bastion" {
  ami                         = var.ami
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  key_name = aws_key_pair.generated_key.key_name

  tags = {
    Name = "bastion-host"
  }
}

# ---------------- OUTPUTS ----------------
output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "app_servers_private_ips" {
  value = data.aws_instances.asg_instances.private_ips
}

data "aws_instances" "asg_instances" {
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.asg.name
  }
}

# ---------------- ANSIBLE INVENTORY ----------------
resource "local_file" "inventory" {
  filename = "${path.module}/ansible/inventory.ini"
  content  = templatefile("${path.module}/ansible/inventory.tpl", {
    app_ips    = data.aws_instances.asg_instances.private_ips
    bastion_ip = aws_instance.bastion.public_ip
    key_path   = "/home/seifkhaled/cloud-devops-automation/ansible/my-keypair.pem"
  })
}
