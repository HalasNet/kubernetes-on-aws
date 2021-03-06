resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH traffic"
  vpc_id      = "${data.terraform_remote_state.layer-base.vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # allow https for kops/kubectl/helm install
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # allow http for ansible install
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # allow ssh for private instance ssh
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.terraform_remote_state.layer-base.vpc_cidr}"]
  }

  # allow 8080 for traefik dashboard (private vpc cidr)
  egress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${data.terraform_remote_state.layer-base.vpc_cidr}"]
  }

  tags {
    Name = "sg_for_bastion"
  }
}

data "aws_iam_policy_document" "bastion-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion_role" {
  name               = "bastion_role"
  path               = "/system/"
  assume_role_policy = "${data.aws_iam_policy_document.bastion-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "EC2-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "Route53-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

resource "aws_iam_role_policy_attachment" "S3-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "IAM-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "VPC-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

resource "aws_iam_policy" "eks_full_access" {
  name        = "eks_full_access"
  description = "A EKSFullAccess policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "eks:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "EKS-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "${aws_iam_policy.eks_full_access.arn}"
}

resource "aws_iam_role_policy_attachment" "STS-assume-role-attach" {
  role       = "${aws_iam_role.bastion_role.name}"
  policy_arn = "arn:aws:iam::549637939820:policy/STSAssumeRoleOnly"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion_profile"
  role = "${aws_iam_role.bastion_role.name}"
}

resource "aws_key_pair" "sandbox-key" {
  key_name   = "sandbox-key"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

resource "aws_instance" "bastion" {
  ami                         = "ami-0bdb1d6c15a40392c"
  instance_type               = "t2.micro"
  vpc_security_group_ids      = ["${aws_security_group.allow_ssh.id}"]
  subnet_id                   = "${data.terraform_remote_state.layer-base.sn_public_a_id}"
  associate_public_ip_address = true
  user_data                   = "${file("install-bastion.sh")}"
  iam_instance_profile        = "${aws_iam_instance_profile.bastion_profile.name}"
  key_name                    = "sandbox-key"

  tags {
    Name = "Bastion"
  }
}

data "aws_route53_zone" "public" {
  name         = "${var.public_dns}"
  private_zone = false
}

resource "aws_route53_record" "bastion-dns" {
  zone_id = "${data.aws_route53_zone.public.zone_id}"
  name    = "bastion.${var.public_dns}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${aws_instance.bastion.public_dns}"]
}

