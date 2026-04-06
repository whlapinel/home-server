# Home Server CDK (us-east-2, VPN-only)

## Prereqs
- Node.js 18+
- AWS CLI configured for the target account in `us-east-2`
- CDK bootstrap: `npx cdk bootstrap aws://ACCOUNT_ID/us-east-2`

For end-to-end steps (seeding SSM env, deploy, port-forward to wg-easy), see `docs/bootstrap.md`.

## Configure
- Decide on (or find) your S3 bucket for restic backups in `us-east-2`.
- Store your env in SSM Parameter Store (SecureString recommended):
  - Name: `/home-server/.env`
  - Value: contents of your `.env` (see `env/.env.example` for keys)

## Deploy
Set once in `cdk.json` context:
```
{
  "app": "npx ts-node --prefer-ts-exts bin/home-server.ts",
  "context": {
    "account": "<YOUR_ACCOUNT_ID>",
    "region": "us-east-2",
    "backupBucketName": "lapinel-home-server-backup",
    "repoUrl": "https://github.com/whlapinel/home-server"
  }
}
```
Then deploy without parameters:
`cd infra/cdk && npm ci && npx cdk bootstrap && npx cdk deploy`

Outputs include instance PublicIp, ElasticIp, and Security Group id. Access via SSM Session Manager (no SSH).

## Notes
- Security group allows only UDP/51820 (WireGuard). No 80/443 from the internet.
- Caddy runs with internal TLS on `*.lapinel-home.arpa` behind VPN.
- An Elastic IP is allocated and attached for a stable WireGuard endpoint (use this for `WG_HOST`).
- To later expose apps publicly, add Route53 records and SG rules for 80/443.
