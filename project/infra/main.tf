locals {
  container_name = var.container_name
  container_port = var.container_port
  common_name = lower("${var.project_name}-${var.environment}")

  tags = {
    Project   = var.project_name
    Environment = var.environment
    Terraform = "true"
  }
}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [locals.common_name]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
  tags = {
    Tier = "Private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
  tags = {
    Tier = "Public"
  }
}

data "aws_ecs_cluster" "ecs" {
  cluster_name = locals.common_name
}
################################################################################
# Service
################################################################################

module "ecs_service" {
  source = "terraform-aws-modules/ecs/aws/modules/service"

  name        = local.common_name
  cluster_arn = data.aws_ecs_cluster.ecs.ecs_cluster_arn

  cpu    = 512
  memory = 1024
  # Container definition(s)
  container_definitions = {
    (local.container_name) = {
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "public.ecr.aws/aws-containers/ecsdemo-frontend:776fd50"
      port_mappings = [
        {
          name          = local.container_name
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]

      # Example image used requires access to write to root filesystem
      readonly_root_filesystem = false

      enable_cloudwatch_logging = false
      log_configuration = {
        logDriver = "awsfirelens"
        options = {
          Name                    = "firehose"
          region                  = local.region
          delivery_stream         = "my-stream"
          log-driver-buffer-limit = "2097152"
        }
      }
      memory_reservation = 100
    }
  }

  load_balancer = {
    service = {
      target_group_arn = element(module.alb.target_group_arns, 0)
      container_name   = local.container_name
      container_port   = local.container_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_ingress_3000 = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb_sg.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-service"
  description = "Service security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  tags = local.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = local.common_name

  load_balancer_type = "application"

  vpc_id          = data.aws_vpc.vpc.vpc_id
  subnets         = data.aws_subnets.private.ids
  security_groups = [module.alb_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name             = "${local.container_name}-${local.common_name}"
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"
    },
  ]

  tags = local.tags
}


resource "aws_ecr_repository" "ecr" {
  name                 = local.common_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
