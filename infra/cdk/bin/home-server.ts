#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { HomeServerStack } from '../lib/home-server-stack';

const app = new cdk.App();

// One solid source of truth: cdk.json context.
const account = app.node.tryGetContext('account') as string | undefined;
const region = (app.node.tryGetContext('region') as string | undefined) ?? 'us-east-2';

if (!account) {
  throw new Error('CDK account not set. Add to infra/cdk/cdk.json -> context.account');
}

const env = { account, region };

new HomeServerStack(app, 'HomeServerStack', { env });
