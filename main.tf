terraform {
apt-get update -y


echo "[userdata] install base packages"
apt-get install -y nginx unzip curl awscli


echo "[userdata] install Node.js 18"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs build-essential


echo "[userdata] create workspace"
mkdir -p /tmp/frontend


echo "[userdata] download frontend from S3"
aws s3 cp s3://${aws_s3_bucket.frontend_bucket.bucket}/${aws_s3_bucket_object.frontend_zip.key} /tmp/frontend.zip --region ${var.aws_region}


echo "[userdata] unzip"
unzip -o /tmp/frontend.zip -d /tmp/frontend || true


# If package.json exists -> build; else use build/ or index.html directly
if [ -f /tmp/frontend/package.json ]; then
cd /tmp/frontend
echo "[userdata] package.json found, running npm ci & build"
npm ci --silent || npm install --silent
npm run build --silent || true
SRC_DIR="/tmp/frontend/build"
elif [ -d /tmp/frontend/build ]; then
SRC_DIR="/tmp/frontend/build"
elif [ -f /tmp/frontend/index.html ]; then
SRC_DIR="/tmp/frontend"
else
echo "[userdata] No build found and no package.json; exiting" > /var/log/user-data.log
exit 1
fi


echo "[userdata] deploying files to nginx html root"
rm -rf /var/www/html/*
cp -r ${SRC_DIR}/* /var/www/html/
chown -R www-data:www-data /var/www/html


systemctl enable nginx
systemctl restart nginx
echo "[userdata] finished"
EOF
}


# Elastic IP (optional but gives stable public IP)
resource "aws_eip" "react_eip" {
instance = aws_instance.react_app.id
vpc = true
}
