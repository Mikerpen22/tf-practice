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

# 3. Create custom route table
resource "aws_route_table" "test-route-table" {
  vpc_id = aws_vpc.test-vpc.id

  route {
    cidr_block = "0.0.0.0/0"    // Default route all traffic to gateway
    gateway_id = aws_internet_gateway.test-gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_internet_gateway.test-gw.id
  }

  tags = {
    Name = "test"
  }
}

# 4. Create a subnet
resource "aws_subnet" "test-subnet-1" {
  vpc_id     = aws_vpc.test-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "test"

  }
}

# 5. Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.test-subnet-1.id
  route_table_id = aws_route_table.test-route-table.id
}


# 6. Create security group to allow port 22(for ssh), 80(Http), 443(Https)
// Security Groups ensure that all the traffic flowing at the instance level is only through your established ports and protocols.
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
data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["591542846629"] # Canonical
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"

  network_interface {
    network_interface_id = aws_network_interface.test-interface.id  // Attach network interface to instance
    device_index = 0  // One instance can have many interfaces
  }


  // Multiline strings can use shell-style "here doc" syntax, with the string starting with a marker like <<EOF and then the string ending with EOF on a line of its own. 
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c "echo you're first web server > /var/www/html/index.html"
              EOF
  tags = {
    Name = "web-server"
  }
}