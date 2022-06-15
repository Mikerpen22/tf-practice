


provider "aws" {
    // access and secret token are stored through aws cli config
    // https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
    profile = "default" 
    region = "us-west-2"
}

# 1. Create VPC
resource "aws_vpc" "test-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "test"
  }
}

# 2. Create Internet Gateway (so VPC can talk to outside world)
resource "aws_internet_gateway" "test-gw" {
  vpc_id = aws_vpc.test-vpc.id
  tags = {
    Name = "test"
  }
}

# 3. Create custom route table for this VPC
resource "aws_route_table" "test-route-table" {
  vpc_id = aws_vpc.test-vpc.id

  // routing rules for ipv4
  // default to route all traffic to gateway
  route {
    cidr_block = "0.0.0.0/0"    
    gateway_id = aws_internet_gateway.test-gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.test-gw.id
  }

  tags = {
    Name = "test"
  }
}

# 4. Create a subnet within VPC
resource "aws_subnet" "test-subnet-1" {
  vpc_id     = aws_vpc.test-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "test"
  }
}

# 5. Associate subnet with route table
// This subnet uses this routing table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.test-subnet-1.id
  route_table_id = aws_route_table.test-route-table.id
}


# 6. Create security group to allow port 22(for ssh), 80(Http), 443(Https) traffic
// Security Groups ensure all the traffic flowing at the instance level only through established ports and protocols.
resource "aws_security_group" "allow_web_traffic" {
  name        = "allow_web_traffic"
  description = "allow web traffic"
  vpc_id      = aws_vpc.test-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Everyone can access
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Everyone can access
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Everyone can access
  }

  egress {
    from_port   = 0   // allowing all ports
    to_port     = 0 
    protocol    = "-1"  // -1: allowing all protocol
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web_traffic"
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4
// Network Interface is usually attached to an instance
// An elastic network interface is a component in VPC that represents a virtual network card
resource "aws_network_interface" "test-interface" {
  subnet_id       = aws_subnet.test-subnet-1.id
  private_ips     = ["10.0.1.50"] // for host
  security_groups = [aws_security_group.allow_web_traffic.id]
}

# 8. Assign an elastic IP(i.e. public ip) to the network interface created in step 7
// This has to be after the internet gateway resource, or terraform will panic
// Since you can't have an public IP if you don't have a gateway
resource "aws_eip" "lb" {
  vpc      = true
  network_interface = aws_network_interface.test-interface.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.test-gw]
}

# 9. Create Ubuntu server and install/enable Apache2
// Data source to get ami
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon-linux-2.id
  instance_type = "t2.micro"
  availability_zone = "us-west-2a"
  key_name = "main-key"
  // Attach network interface to instance
  // often wanna make sure they're in the same availability zone
  network_interface {
    network_interface_id = aws_network_interface.test-interface.id  // Attach network interface to instance
    device_index = 0  // One instance can have many interfaces
  }


  // Multiline strings can use shell-style "here doc" syntax, with the string starting with a marker like <<EOF and then the string ending with EOF on a line of its own. 
   user_data = <<-EOF
                 #!/bin/bash
                 sudo yum update -y
                 sudo yum install httpd -y
                 sudo systemctl start httpd -y
                 sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                 EOF
  tags = {
    Name = "web-server"
  }
}