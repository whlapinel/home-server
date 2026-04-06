#! /bin/bash

cd /home/whlapinel/home_server/home-server/

aws ssm put-parameter \
--name "/home-server/.env" \
--value "$(cat .env.remote)" \
--type SecureString \
--overwrite \
--region us-east-2