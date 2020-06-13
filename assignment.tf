
provider "aws" {

  region     = "ap-south-1"
  profile    = "shreya"

}


//GETING VPC ID

data "aws_vpc" "selected" {
    default = true
}

locals {
    vpc_id    = data.aws_vpc.selected.id
}



// CREATING KEY PAIR

resource "tls_private_key" "this" {

	algorithm = "RSA"

}

resource "local_file" "private_key" {
    content         =  tls_private_key.this.private_key_pem
    filename        =  "terrakey.pem"
}

resource "aws_key_pair" "webserver_key" {
    key_name   = "terrakey"
    public_key = tls_private_key.this.public_key_openssh
}



// CREATING SECURITY GROUP

resource "aws_security_group" "customsg" {
  name        = "myterrasg"
  description = "https, ssh, icmp"
  vpc_id      = local.vpc_id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ping-icmp"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security_group_task"
  }
}

// LAUNCHING AN EC2 INSTANCE 

resource "aws_instance" "terra_instance" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name 	= aws_key_pair.webserver_key.key_name
  security_groups = [ aws_security_group.customsg.name ]


  // SETTING UP CONNECTION

  connection {
	type = "ssh"
	user = "ec2-user"
	private_key = tls_private_key.this.private_key_pem
	host = aws_instance.terra_instance.public_ip
  }

  // WRITING COMMANDS IN CLOUD O.S.

  provisioner "remote-exec"{
	inline = [
		"sudo yum install httpd -y",
		"sudo systemctl restart httpd",
		"sudo systemctl enable httpd",
		"sudo yum install git -y"
		]
  }

  tags = {
    Name = "terraos"
  }

}


// CREATING AN EBS VOLUME

resource "aws_ebs_volume" "terraesb" {

	availability_zone = aws_instance.terra_instance.availability_zone
	size = 1
	type = "gp2"
	tags = {
		Name = "terrapd"
	}
}


// ATTACHING EBS VOLUME

resource "aws_volume_attachment" "ebs_attach"{
	
	device_name = "/dev/sdh"
	volume_id = "${aws_ebs_volume.terraesb.id}"
	instance_id = "${aws_instance.terra_instance.id}"
	
}

output "myos_ip"{
	value = aws_instance.terra_instance.public_ip
}

// RUNNING COMMANDS ON LOCAL SYSTEM USING TERRAFORM

resource "null_resource" "null_local_1"{

	provisioner "local-exec" {
		command = "echo ${aws_instance.terra_instance.public_ip} > publicip.txt"
	}
}

// RUNNING COMMANDS ON REMOTE SYSTEM USING TERRAFORM


resource "null_resource" "null_remote_2"{
	
	depends_on = [
		aws_volume_attachment.ebs_attach,
	]

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key  = tls_private_key.this.private_key_pem
		host = aws_instance.terra_instance.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo mkfs.ext4 /dev/xvdh",
			"sudo mount /dev/xvdh /var/www/html",
			"sudo rm -rf /var/www/html",
			"sudo git clone https://github.com/Shreya-agrawal-2000/lwtraining_task1.git /var/www/html/"
			
		]
	}

	provisioner "remote-exec" {
        when    = destroy
        inline  = [
            "sudo umount /var/www/html"
        ]
    }
}


/*
resource "null_resource" "null_local_2"{
	depends_on = [
		null_resource.null_remote_2,
	]

	provisioner "local-exec"{
		command = "chrome ${aws_instance.terra_instance.public_ip}"
	}
}
*/


// CREATING S3 BUCKET

resource "aws_s3_bucket" "myterrabucket" {
    bucket  = "meriterrabucket"
    acl     = "public-read"

	provisioner "local-exec" {
        command =  "git clone https://github.com/Shreya-agrawal-2000/webserver-image.git webserver-image" 
    	}

	provisioner "local-exec" {
        when        =   destroy
        command  =   "echo Y | rmdir /s webserver-image"
    	}

}

resource "aws_s3_bucket_object" "image-upload" {
    bucket  = aws_s3_bucket.myterrabucket.bucket
    key     = "myphoto.jpg"
    source  = "webserver-image/Mykines-lighthouse.jpg"
    acl     = "public-read"
}



// CREATING CLOUD FRONT DISTRIBUTION


variable "var1" {default = "S3-"}


locals {
    s3_origin_id = "${var.var1}${aws_s3_bucket.myterrabucket.bucket}"
    image_url = "${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image-upload.key}"
}



resource "aws_cloudfront_distribution" "s3_distribution" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }

enabled             = true

origin {
        domain_name = aws_s3_bucket.myterrabucket.bucket_domain_name
        origin_id   = local.s3_origin_id
    }


restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }


viewer_certificate {
        cloudfront_default_certificate = true
    }


connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.terra_instance.public_ip
        port    = 22
        private_key = tls_private_key.this.private_key_pem
    }


provisioner "remote-exec" {
        inline  = [
            # "sudo su << \"EOF\" \n echo \"<img src='${self.domain_name}'>\" >> /var/www/html/test.html \n \"EOF\""
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image-upload.key}'>\" >> /var/www/html/test.html",
            "EOF"
        ]
    }
}
