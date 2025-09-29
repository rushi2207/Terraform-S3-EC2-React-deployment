output "instance_id" {
value = aws_instance.react_app.id
}


output "instance_public_ip" {
value = aws_eip.react_eip.public_ip
}


output "instance_public_dns" {
value = aws_instance.react_app.public_dns
}


output "website_url" {
value = format("http://%s", aws_eip.react_eip.public_ip)
}


output "s3_bucket_name" {
value = aws_s3_bucket.frontend_bucket.bucket
}


output "s3_object_key" {
value = aws_s3_bucket_object.frontend_zip.key
}
