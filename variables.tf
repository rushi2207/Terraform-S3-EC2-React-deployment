variable "aws_region" {
  default = "us-east-1"
}

variable "key_name" {
  default     = "case-1"
  description = "EC2 key pair name"
}


variable "github_username" {
  default     = "rushi2207"
  description = "GitHub username"
}



variable "github_repo" {
  default     = "https://github.com/rushi2207/Simple-react-app.git"
  description = "GitHub repo URL"
}
