resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "My VPC"
  }
}

resource "aws_subnet" "public_eu_central_1a" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.0/26"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "Public Subnet eu_central-1a"
  }
}

resource "aws_subnet" "public_eu_central_1b" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/26"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "Public Subnet eu_central_1b"
  }
}

resource "aws_subnet" "private_eu_central_1a" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.2.0/26"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "Private Subnet eu_central-1a"
  }
}

resource "aws_subnet" "private_eu_central_1b" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.3.0/26"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "Private Subnet eu_central_1b"
  }
}

resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "My VPC - Internet Gateway"
  }
}

resource "aws_route_table" "my_vpc_public" {
    vpc_id = aws_vpc.my_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.my_vpc_igw.id
    }

    tags = {
        Name = "Public Subnets Route Table for My VPC"
    }
}


resource "aws_route_table_association" "my_vpc_eu_central_1a_public" {
    subnet_id = aws_subnet.public_eu_central_1a.id
    route_table_id = aws_route_table.my_vpc_public.id
}

resource "aws_route_table_association" "my_vpc_eu_central_1b_public" {
    subnet_id = aws_subnet.public_eu_central_1b.id
    route_table_id = aws_route_table.my_vpc_public.id
}

resource "aws_route_table" "my_vpc_private" {
    vpc_id = aws_vpc.my_vpc.id

    tags = {
        Name = "Local Route Table for Isolated Private Subnet"
    }
}

resource "aws_route_table_association" "my_vpc_eu_central_1a_private" {
    subnet_id = aws_subnet.private_eu_central_1a.id
    route_table_id = aws_route_table.my_vpc_private.id
}

resource "aws_route_table_association" "my_vpc_eu_central_1b_private" {
    subnet_id = aws_subnet.private_eu_central_1b.id
    route_table_id = aws_route_table.my_vpc_private.id
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound connections"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP Security Group"
  }
}

resource "aws_launch_configuration" "web" {
  name_prefix = "web-"

  image_id = "ami-05d34d340fb1d89e5" # Amazon Linux 2 AMI (HVM), SSD Volume Type
  instance_type = "t2.micro"
  key_name = "EC2 proje"

  security_groups = [ aws_security_group.allow_http.id ]
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
  user_data = file("entry-script.sh")
}

resource "aws_security_group" "alb" {
  name        = "terraform_alb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = aws_vpc.my_vpc.id


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_alb" "alb" {
  name            = "terraform-example-alb"
  security_groups = [aws_security_group.alb.id]
  subnets         = [
    aws_subnet.public_eu_central_1a.id,
    aws_subnet.public_eu_central_1b.id
  ]

}

resource "aws_alb_target_group" "group" {
  name     = "terraform-example-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
  stickiness {
    type = "lb_cookie"
  }
  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/login"
    port = 80
  }
}

resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = aws_alb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.group.arn
    type             = "forward"
  }
}

resource "aws_autoscaling_attachment" "alb_autoscale" {
  alb_target_group_arn   = aws_alb_target_group.group.arn
  autoscaling_group_name = aws_autoscaling_group.web.id
}


resource "aws_autoscaling_group" "web" {
  name = aws_launch_configuration.web.name

  min_size             = 1
  desired_capacity     = 1
  max_size             = 3
  
  launch_configuration = aws_launch_configuration.web.name

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier  = [
    aws_subnet.public_eu_central_1a.id,
    aws_subnet.public_eu_central_1b.id
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }

}

resource "aws_autoscaling_policy" "web_policy_up" {
  name = "web_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_autoscaling_policy" "web_policy_down" {
  name = "web_policy_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

output "alb_dns_name" {
  value = aws_alb.alb.dns_name
}
