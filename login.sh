#! /bin/bash

source .env.dev

aws sso login --profile $AWS_PROFILE