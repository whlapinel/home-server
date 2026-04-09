#! /bin/bash

cd /home/whlapinel/home_server/home-server/

source .env.dev

aws ssm put-parameter \
--name "/home-server/.env" \
--value "$(cat .env.remote)" \
--type SecureString \
--overwrite \
--region us-east-2 \
--profile $AWS_PROFILE