#! /bin/bash

# to run on ec2 instance

aws ssm get-parameter \
  --name "/home-server/.env" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-2 \
  > /etc/home-server/.env
