provider "aws" {
  region = "us-east-2" # Switched to Ohio
}

# 1. ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name                 = "my-simple-app-repo"
  image_tag_mutability = "MUTABLE"
  #force_destroy        = true # Ensure your AWS provider is v4.22+ or delete this line
}

# 2. ECS Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "my-simple-app-cluster"
}

# 3. IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role_unique" # Added unique suffix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 4. Security Group (Allows you to actually see the website)
resource "aws_security_group" "ecs_sg" {
  name        = "allow_http_ecs"
  description = "Allow HTTP inbound traffic"
  vpc_id      = data.aws_vpc.default.id

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

# 5. ECS Task Definition
resource "aws_ecs_task_definition" "app_task" {
  family                   = "my-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "my-app-container"
    image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

# 6. Data Sources for Network (Should work automatically in us-east-2)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 7. ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "my-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs_sg.id]
  }
}

# Output the Repository URL so you can double check it
output "ecr_repository_url" {
  value = aws_ecr_repository.app_repo.repository_url
}