variable "aws_region" {
type = string
default = "us-east-1"
}


variable "instance_type" {
type = string
default = "t2.micro"
}


variable "key_name" {
type = string
description = "Existing EC2 key pair name in the selected AWS account/region. If you don't have one create it or change this variable."
default = "case-1"
}


variable "bucket_name_prefix" {
type = string
default = "react-frontend"
}
