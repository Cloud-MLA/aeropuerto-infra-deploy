# RUNBOOK.md 1.8 — ALB interno frente a las 2 VM-PROD.

resource "aws_lb" "internal" {
  name               = "aeropuerto-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private[*].id

  tags = { Name = "aeropuerto-alb" }
}

resource "aws_lb_target_group" "vm_prod" {
  name     = "tg-vm-prod"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = var.alb_health_check_path
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = { Name = "tg-vm-prod" }
}

resource "aws_lb_target_group_attachment" "vm_prod" {
  count            = 2
  target_group_arn = aws_lb_target_group.vm_prod.arn
  target_id        = aws_instance.vm_prod[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vm_prod.arn
  }
}
