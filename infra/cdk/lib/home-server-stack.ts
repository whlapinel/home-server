import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';

export class HomeServerStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Configuration via CDK context (see infra/cdk/cdk.json)
    const backupBucketName = (this.node.tryGetContext('backupBucketName') as string) ?? 'lapinel-home-server-backup';
    const repoUrl = (this.node.tryGetContext('repoUrl') as string) ?? 'https://github.com/whlapinel/home-server';

    // Use default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    // Security group: VPN-only exposure (WireGuard UDP 51820). No 80/443 ingress.
    const sg = new ec2.SecurityGroup(this, 'HomeServerSg', {
      vpc,
      description: 'Home server security group (VPN-only).',
      allowAllOutbound: true,
    });
    sg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.udp(51820), 'WireGuard UDP');

    // IAM role with SSM and optional S3/SSM Parameter Store access
    const role = new iam.Role(this, 'HomeServerRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
    });
    role.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'));

    // S3 permissions for backups
    const bucketArn = `arn:${cdk.Aws.PARTITION}:s3:::${backupBucketName}`;
    role.addToPolicy(new iam.PolicyStatement({
      actions: ['s3:ListBucket'],
      resources: [bucketArn],
    }));
    role.addToPolicy(new iam.PolicyStatement({
      actions: ['s3:GetObject', 's3:PutObject', 's3:DeleteObject'],
      resources: [`${bucketArn}/*`],
    }));

    // SSM Parameter Store read for /home-server/.env
    role.addToPolicy(new iam.PolicyStatement({
      actions: ['ssm:GetParameter', 'ssm:GetParameters'],
      resources: [
        `arn:${cdk.Aws.PARTITION}:ssm:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:parameter/home-server/.env`,
      ],
    }));

    // Route53 permissions for Caddy Let's Encrypt DNS challenge
    role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'route53:GetChange',
        'route53:ChangeResourceRecordSets',
        'route53:ListResourceRecordSets',
      ],
      resources: [
        'arn:aws:route53:::hostedzone/Z02298411YL43N517DY88',
        'arn:aws:route53:::change/*',
      ],
    }));
    role.addToPolicy(new iam.PolicyStatement({
      actions: ['route53:ListHostedZonesByName'],
      resources: ['*'],
    }));

    // Amazon Linux 2023 via SSM public parameter (x86_64)
    const machineImage = ec2.MachineImage.fromSsmParameter(
      '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64',
      { os: ec2.OperatingSystemType.LINUX }
    );

    // User data: direct bootstrap without external cloud-init (fail-fast, verbose)
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'set -euxo pipefail',
      'LOG=/var/log/home-server-bootstrap.log',
      'exec > >(tee -a "$LOG") 2>&1',
      'echo "[bootstrap] Starting at $(date -Is)"',
      'dnf update -y',
      'dnf makecache -y',
      // Install Docker from AL2023 repos and tools
      'dnf install -y docker git awscli bzip2 ca-certificates',
      // Install Docker Compose v2 plugin (not included in AL2023 docker package)
      'mkdir -p /usr/local/lib/docker/cli-plugins',
      'curl -SL https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose',
      'chmod +x /usr/local/lib/docker/cli-plugins/docker-compose',
      // Install restic via official release (pin version)
      'echo "[bootstrap] Installing restic 0.18.1"',
      'curl -fsSL -o /usr/local/bin/restic.bz2 https://github.com/restic/restic/releases/download/v0.18.1/restic_0.18.1_linux_amd64.bz2',
      'bzip2 -df /usr/local/bin/restic.bz2',
      'chmod +x /usr/local/bin/restic',
      'restic version',
      'if id ec2-user >/dev/null 2>&1; then usermod -aG docker ec2-user; fi',
      'sysctl -w net.ipv4.ip_forward=1',
      'sysctl -w net.ipv4.conf.all.src_valid_mark=1',
      'systemctl enable --now docker',
      'echo "[bootstrap] Waiting for Docker daemon..."',
      'until docker info >/dev/null 2>&1; do sleep 2; done',
      'mkdir -p /etc/home-server /opt/home-server',
      'echo "[bootstrap] Fetching /home-server/.env from SSM Parameter Store"',
      `aws ssm get-parameter --region ${cdk.Stack.of(this).region} --name "/home-server/.env" --with-decryption --query 'Parameter.Value' --output text > /etc/home-server/.env`,
      'test -s /etc/home-server/.env || { echo "[bootstrap][error] /etc/home-server/.env is missing or empty"; exit 1; }',
      `REPO_URL="${repoUrl}"`,
      'echo "[bootstrap] Cloning or updating repo: $REPO_URL"',
      '[ -d /opt/home-server/.git ] || git clone "$REPO_URL" /opt/home-server',
      'cd /opt/home-server && git rev-parse --is-inside-work-tree',
      'cd /opt/home-server && git pull --ff-only',
      'ln -sf /etc/home-server/.env /opt/home-server/.env',
      'echo "[bootstrap] Bringing up Docker Compose stack (remote override)"',
      'cd /opt/home-server && docker compose -f docker-compose.yml -f docker-compose.remote.yml --env-file /etc/home-server/.env up -d --build',
      'echo "[bootstrap] Completed at $(date -Is)"'
    );

    const instance = new ec2.Instance(this, 'HomeServerInstance', {
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      instanceType: new ec2.InstanceType('t3.small'),
      machineImage,
      securityGroup: sg,
      role,
      userData,
    });

    // Allocate and associate an Elastic IP for a stable WireGuard endpoint
    const eip = new ec2.CfnEIP(this, 'HomeServerEip', { domain: 'vpc' });
    new ec2.CfnEIPAssociation(this, 'HomeServerEipAssoc', {
      allocationId: eip.attrAllocationId,
      instanceId: instance.instanceId,
    });

    // Outputs
    new cdk.CfnOutput(this, 'InstanceId', { value: instance.instanceId });
    new cdk.CfnOutput(this, 'PublicIp', { value: instance.instancePublicIp });
    new cdk.CfnOutput(this, 'SgId', { value: sg.securityGroupId });
    new cdk.CfnOutput(this, 'BackupBucketNameOutput', { value: backupBucketName || '<unset>' });
    new cdk.CfnOutput(this, 'ElasticIp', { value: eip.attrPublicIp });
  }
}
