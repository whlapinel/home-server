#! /bin/bash

aws ssm start-session \
  --target i-0ebd849e8579d2776 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["51821"],"localPortNumber":["51821"]}' \
  --region us-east-2 \
  --profile AdministratorAccess-955852928464