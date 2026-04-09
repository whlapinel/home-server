#!/bin/bash

source .env.dev

aws ssm start-session --profile $AWS_PROFILE --target $INSTANCE_ID