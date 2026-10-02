variable "aws_region" {
  description = "AWS region for the assessment lab."
  type        = string
  default     = "us-east-1"
}

variable "aws_availability_zone" {
  description = "Availability Zone for the assessment lab."
  type        = string
  default     = "us-east-1a"
}

variable "ubuntu_ami_id" {
  description = "Ubuntu 24.04 AMI ID for us-east-1."
  type        = string
  default     = "ami-0045d7fc2ad003464"
}

variable "project_name" {
  type    = string
  default = "fynd-devsecops"
}

variable "ssh_key_name" {
  description = "Existing EC2 key-pair name in the target AWS region."
  type        = string
  default     = ""
}

variable "admin_cidr" {
  description = "Your public IP/CIDR for SSH. Use /32 where possible."
  type        = string
}

variable "app_instance_type" {
  description = "Assignment target is about 2 vCPU/4 GiB."
  type        = string
  default     = "t3.medium"
}

variable "wazuh_instance_type" {
  description = "Assignment target is about 4 vCPU/8 GiB."
  type        = string
  default     = "t3.medium"
}

variable "wireguard_cidr" {
  type    = string
  default = "10.8.0.0/24"
}

variable "use_existing_network" {
  description = "Reuse an existing VPC/subnet when the AWS account VPC quota prevents creating another VPC."
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "Existing VPC ID used when use_existing_network is true."
  type        = string
  default     = "vpc-07a9b5921a6ed237a"
}

variable "existing_subnet_id" {
  description = "Existing subnet ID used when use_existing_network is true."
  type        = string
  default     = "subnet-0d2d14efabc327733"
}
