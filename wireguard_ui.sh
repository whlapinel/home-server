#! /bin/bash

aws ssm start-session \
  --target i-058ffae9eeb79b53c \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["51821"],"localPortNumber":["51821"]}' \
  --region us-east-2