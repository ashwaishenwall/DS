data "aws_vpc" "existing" {
  count = var.use_existing_network ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_subnet" "existing" {
  count = var.use_existing_network ? 1 : 0
  id    = var.existing_subnet_id
}

locals {
  vpc_id              = var.use_existing_network ? data.aws_vpc.existing[0].id : aws_vpc.lab[0].id
  subnet_id           = var.use_existing_network ? data.aws_subnet.existing[0].id : aws_subnet.public[0].id
  availability_zone   = var.use_existing_network ? data.aws_subnet.existing[0].availability_zone : var.aws_availability_zone
  juice_shop_manifest = file("${path.module}/../k8s/juice-shop.yaml")

  app_reconcile_script = templatefile("${path.module}/../scripts/app-reconcile.sh.tftpl", {
    wazuh_private_ip = aws_instance.wazuh.private_ip
    project_name     = var.project_name
    wireguard_cidr   = var.wireguard_cidr
  })

  app_bootstrap_script = templatefile("${path.module}/../scripts/app-bootstrap.sh.tftpl", {
    project_name         = var.project_name
    wazuh_private_ip     = aws_instance.wazuh.private_ip
    wireguard_cidr       = var.wireguard_cidr
    juice_shop_manifest  = local.juice_shop_manifest
    app_reconcile_script = local.app_reconcile_script
  })
}

resource "aws_vpc" "lab" {
  count                = var.use_existing_network ? 0 : 1
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = var.use_existing_network ? 0 : 1
  vpc_id                  = local.vpc_id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = var.aws_availability_zone
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-public" }
}

resource "aws_internet_gateway" "this" {
  count  = var.use_existing_network ? 0 : 1
  vpc_id = local.vpc_id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  count  = var.use_existing_network ? 0 : 1
  vpc_id = local.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = var.use_existing_network ? 0 : 1
  subnet_id      = local.subnet_id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "app" {
  name        = var.use_existing_network ? "${var.project_name}-app-ci" : "${var.project_name}-app"
  description = "Application/WAF/VPN security group"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from administrator"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "WireGuard"
    protocol    = "udp"
    from_port   = 51820
    to_port     = 51820
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WAF public listener. Final access is intended to be restricted to
  # VPN users/evaluator IP; this CIDR is therefore the admin/evaluator CIDR.
  ingress {
    description = "WAF HTTP from evaluator"
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "WAF HTTP from WireGuard clients"
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = [var.wireguard_cidr]
  }

  # Direct-origin port is deliberately NOT opened.
  # Juice Shop is exposed only as a ClusterIP service and is blocked
  # at the AWS security-group boundary.

  egress {
    description = "HTTPS egress for package repositories and AWS services"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP egress for package repositories"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Wazuh agent enrollment and events"
    protocol    = "tcp"
    from_port   = 1514
    to_port     = 1515
    cidr_blocks = ["10.20.1.0/24"]
  }

  tags = { Name = var.use_existing_network ? "${var.project_name}-app-sg-ci" : "${var.project_name}-app-sg" }
}

resource "aws_security_group" "wazuh" {
  name        = var.use_existing_network ? "${var.project_name}-wazuh-ci" : "${var.project_name}-wazuh"
  description = "Private Wazuh access"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from administrator"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [var.admin_cidr]
  }

  # Agent enrollment and event transport from the app SG.
  ingress {
    description     = "Wazuh agent enrollment"
    protocol        = "tcp"
    from_port       = 1515
    to_port         = 1515
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Wazuh agent events"
    protocol        = "tcp"
    from_port       = 1514
    to_port         = 1514
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Wazuh API from app verifier"
    protocol        = "tcp"
    from_port       = 55000
    to_port         = 55000
    security_groups = [aws_security_group.app.id]
  }

  # Indexer is intentionally not exposed to the Internet.
  # The verifier reaches it over the VPC/private IP.
  ingress {
    description     = "Indexer API from app verifier"
    protocol        = "tcp"
    from_port       = 9200
    to_port         = 9200
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description = "Wazuh dashboard from WireGuard clients"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.wireguard_cidr]
  }

  ingress {
    description     = "Wazuh dashboard via VPN gateway"
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "HTTPS egress for Wazuh downloads and AWS services"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP egress for package repositories"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.use_existing_network ? "${var.project_name}-wazuh-sg-ci" : "${var.project_name}-wazuh-sg" }
}

resource "aws_ebs_volume" "wazuh_data" {
  availability_zone = local.availability_zone
  size              = 50
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "${var.project_name}-wazuh-data" }
}

resource "aws_instance" "wazuh" {
  ami                         = var.ubuntu_ami_id
  instance_type               = var.wazuh_instance_type
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.wazuh.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  # The Wazuh bootstrap script is larger than EC2's 16 KiB raw user-data limit.
  # Compress it before base64 encoding so cloud-init can consume the complete script.
  user_data_base64 = base64gzip(templatefile("${path.module}/../scripts/wazuh-bootstrap.sh.tftpl", {
    project_name = var.project_name
  }))

  tags = {
    Name = "${var.project_name}-wazuh"
    Role = "wazuh"
  }
}

resource "aws_volume_attachment" "wazuh_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.wazuh_data.id
  instance_id = aws_instance.wazuh.id
}

resource "aws_instance" "app" {
  ami                         = var.ubuntu_ami_id
  instance_type               = var.app_instance_type
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(<<-EOT
#!/usr/bin/env bash
set -Eeuo pipefail
exec > >(tee -a /var/log/fynd-app-bootstrap.log) 2>&1

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

log "[APP] Starting application bootstrap"
cat >/usr/local/bin/fynd-app-bootstrap.sh <<'APP_BOOTSTRAP'
${local.app_bootstrap_script}
APP_BOOTSTRAP
chmod 700 /usr/local/bin/fynd-app-bootstrap.sh
bash /usr/local/bin/fynd-app-bootstrap.sh
log "[APP] Application bootstrap completed"
EOT
  )

  tags = {
    Name = "${var.project_name}-app"
    Role = "application"
  }
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "wazuh_public_ip" {
  value = aws_instance.wazuh.public_ip
}

output "wazuh_private_ip" {
  value = aws_instance.wazuh.private_ip
}

output "wazuh_dashboard_url" {
  value = "https://${aws_instance.wazuh.private_ip}/"
}

output "app_waf_url" {
  value = "http://${aws_instance.app.public_ip}:8080/"
}
