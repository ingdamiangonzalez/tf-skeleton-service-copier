variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "container_name" {
  description = "Container name"
  type        = string
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default = "us-east-1"
}