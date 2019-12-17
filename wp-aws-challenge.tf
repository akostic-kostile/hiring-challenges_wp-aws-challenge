##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}

variable "region" {
  default = "eu-central-1"
}

variable "network_address_space" {
  default = "10.120.0.0/16"
}

variable "instance_count" {
  default = 2
}

variable "subnet_count" {
  default = 2
}

variable "ec2_instance_type" {
  default = "t2.micro"
}

variable "wordpress_db_name" {
  default = "wordpress"
}

variable "wordpress_db_user" {
  default = "wordpress"
}

variable "wordpress_db_password" {
  default = "wordpress"
}

variable "rds_instance_type" {
  default = "db.t2.micro"
}
##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block = var.network_address_space

}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

}

resource "aws_subnet" "subnet" {
  count                   = var.subnet_count
  cidr_block              = cidrsubnet(var.network_address_space, 8, count.index)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

}

resource "aws_db_subnet_group" "rds-subnet-group" {
  name       = "rds-subnet-group"
  subnet_ids = aws_subnet.subnet[*].id

}

# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}

resource "aws_route_table_association" "rta-subnet" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.rtb.id

}

# SECURITY GROUPS #
resource "aws_security_group" "elb-sg" {
  name   = "elb_sg"
  vpc_id = aws_vpc.vpc.id

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# wordpress security group 
resource "aws_security_group" "wordpress-sg" {
  name   = "wordpress_sg"
  vpc_id = aws_vpc.vpc.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.network_address_space]
  }

  # allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# rds security group
resource "aws_security_group" "rds-sg" {
  name   = "rds_sg"
  vpc_id = aws_vpc.vpc.id

  # open port 3306 from VPC
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.network_address_space]
  }

  # allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# LOAD BALANCER #
resource "aws_elb" "web" {
  name = "wordpress-elb"

  subnets         = aws_subnet.subnet[*].id
  security_groups = [aws_security_group.elb-sg.id]
  instances       = aws_instance.wordpress[*].id

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/wp-admin/install.php" # classic elb does not consider 302 a valid response code so we can not use / as health check path
    interval            = 30
  }

}

resource "aws_lb_cookie_stickiness_policy" "wordpress-sticky" {
  name                     = "wordpress-sticky-policy"
  load_balancer            = aws_elb.web.id
  lb_port                  = 80
  cookie_expiration_period = 600

}

# INSTANCES #
resource "aws_instance" "wordpress" {
  count                  = var.instance_count
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.subnet[count.index % var.subnet_count].id
  vpc_security_group_ids = [aws_security_group.wordpress-sg.id]
  key_name               = var.key_name
  depends_on             = [aws_db_instance.wordpress-db] 

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)

  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd24 php73 php73-mysqlnd -y",
      "cd /var/www/html; sudo curl -LO http://wordpress.org/latest.tar.gz; sudo tar -xzvf latest.tar.gz",
      "sudo chown apache:apache -R wordpress/",
      "sudo mv wordpress/wp-config-sample.php wordpress/wp-config.php",
      "sudo sed -i 's/database_name_here/${var.wordpress_db_name}/g' wordpress/wp-config.php",
      "sudo sed -i 's/username_here/${var.wordpress_db_user}/g' wordpress/wp-config.php",
      "sudo sed -i 's/password_here/${var.wordpress_db_password}/g' wordpress/wp-config.php",
      "sudo sed -i 's/localhost/${aws_db_instance.wordpress-db.endpoint}/g' wordpress/wp-config.php",
      "sudo sed -i 's%DocumentRoot \"/var/www/html\"%DocumentRoot \"/var/www/html/wordpress\"%g' /etc/httpd/conf/httpd.conf",
      "sudo service httpd start",
      "sudo chkconfig httpd on"
    ]
  }

}

# RDS
resource "aws_db_instance" "wordpress-db" {
  allocated_storage           = 10
  storage_type                = "gp2"
  engine                      = "mysql"
  engine_version              = "5.7"
  instance_class              = var.rds_instance_type
  name                        = var.wordpress_db_name
  username                    = var.wordpress_db_user
  password                    = var.wordpress_db_password
  parameter_group_name        = "default.mysql5.7"
  db_subnet_group_name        = aws_db_subnet_group.rds-subnet-group.name
  vpc_security_group_ids      = [aws_security_group.rds-sg.id]
  multi_az                    = true
  skip_final_snapshot         = true

}

##################################################################################
# OUTPUT
##################################################################################

output "aws_elb_public_dns" {
  value = aws_elb.web.dns_name

}
