resource "aws_lightsail_instance" "web" {
  name              = var.lightsail_instance_name
  availability_zone = var.lightsail_availability_zone
  blueprint_id      = var.lightsail_blueprint_id
  bundle_id         = var.lightsail_bundle_id
  key_pair_name     = var.lightsail_key_pair_name
  user_data         = var.lightsail_user_data_path == null ? null : file(var.lightsail_user_data_path)
}

resource "aws_lightsail_static_ip" "web" {
  count = var.manage_lightsail_static_ip ? 1 : 0

  name = var.lightsail_static_ip_name
}

resource "aws_lightsail_static_ip_attachment" "web" {
  count = var.manage_lightsail_static_ip ? 1 : 0

  static_ip_name = aws_lightsail_static_ip.web[0].name
  instance_name  = aws_lightsail_instance.web.name
}

resource "aws_lightsail_instance_public_ports" "web" {
  count = var.manage_lightsail_public_ports ? 1 : 0

  instance_name = aws_lightsail_instance.web.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }
}
