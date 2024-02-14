provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "example_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.example_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.example_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_route_table" "public_route_table_1" {
  vpc_id = aws_vpc.example_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example_igw.id
  }

  tags = {
    Name = "Public Route Table 1"
  }
}

resource "aws_route_table" "public_route_table_2" {
  vpc_id = aws_vpc.example_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example_igw.id
  }

  tags = {
    Name = "Public Route Table 2"
  }
}

resource "aws_route_table_association" "public_subnet_association_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table_1.id
}

resource "aws_route_table_association" "public_subnet_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table_2.id
}

resource "aws_internet_gateway" "example_igw" {
  vpc_id = aws_vpc.example_vpc.id
}

resource "aws_security_group" "public_subnet_sg_1" {
  vpc_id = aws_vpc.example_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.elb_sg.id]
  }

  tags = {
    Name = "Public Subnet Security Group 1"
  }
}

resource "aws_security_group" "public_subnet_sg_2" {
  vpc_id = aws_vpc.example_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.elb_sg.id]
  }

  tags = {
    Name = "Public Subnet Security Group 2"
  }
}

output "public_subnet_1_id" {
  value = aws_subnet.public_subnet_1.id
}

output "public_subnet_2_id" {
  value = aws_subnet.public_subnet_2.id
}
resource "aws_launch_configuration" "example1" {
  name = "custom-example1-launchconfig"
  # Ubuntu Server 18.04 LTS (HVM), SSD Volume Type in ap-south-01
  image_id        = "ami-06aa3f7caf3a30282"
  instance_type   = "t2.micro"
  associate_public_ip_address = true
  security_groups = [aws_security_group.public_subnet_sg_1.id, aws_security_group.public_subnet_sg_2.id]
  user_data = <<-EOF
              #!/bin/bash
              echo '<html><body><h1>Hello </h1></html>' > index.html
              nohup busybox httpd -f -p "${80}" &
              EOF

  # Whenever using a launch configuration with an auto scaling group, you must set below
  lifecycle {
    create_before_destroy = true
  }
}
# Define auto-scaling group
resource "aws_autoscaling_group" "example" {
  name                     = "example-asg"
  launch_configuration    = aws_launch_configuration.example1.name
  min_size                 = 2
  max_size                 = 4
  desired_capacity         = 2
  vpc_zone_identifier      = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  health_check_grace_period = 30
  health_check_type = "EC2"
  target_group_arns = [aws_lb_target_group.custom.arn]
}
# Create Target group

resource "aws_lb_target_group" "custom" {
  name       = "Demo-TargetGroup-custom"
  depends_on = [aws_vpc.example_vpc]
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.example_vpc.id
  health_check {
    interval            = 70
    path                = "/index.html"
    port                = 80
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 30
    protocol            = "HTTP"
    matcher             = "200,202"
  }
}
# Create ALB

resource "aws_lb" "custom" {
  name               = "Demo-alb-custom"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
}

# Create ALB Listener 

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.custom.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.custom.arn
  }
}

