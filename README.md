# CrowdStrike AWS SOAR Actions

CloudFormation templates for deploying CrowdStrike Falcon Fusion SOAR (Security Orchestration, Automation, and Response) actions to AWS with granular, action-level IAM permissions.

[![Launch Stack](https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png)](https://console.aws.amazon.com/cloudformation/home#/stacks/create/review?templateURL=https://s3.amazonaws.com/falcon-aws-soar-actions-templates/templates/crowdstrike-soar-actions-granular.yaml&stackName=CrowdStrike-SOAR-Actions)
[![Validate Templates](https://github.com/yannhowe/falcon-aws-soar-actions/actions/workflows/validate.yml/badge.svg)](https://github.com/yannhowe/falcon-aws-soar-actions/actions/workflows/validate.yml)

## Architecture

```
┌──────────────────────┐
│   CrowdStrike Falcon │
│   Fusion SOAR        │
└──────────┬───────────┘
           │ sts:AssumeRole
           ▼
┌──────────────────────┐
│  CrowdStrike Role    │   CrowdStrike-managed account
│  (region-specific)   │   (shared across all customers)
│                      │
└──────────┬───────────┘
           │ sts:AssumeRole + ExternalId
           ▼
┌──────────────────────┐
│  Your Role           │   Your AWS account(s)
│  CrowdStrike         │   Deployed via StackSets
│  AutomatedResponse   │
└──────────┬───────────┘
           │ Per-action IAM policies
           ▼
┌──────────────────────────────────────────┐
│  Your AWS Resources                      │
│  EC2 · IAM · S3 · Lambda · GuardDuty    │
│  WAF · SSM · SNS · SQS · EFS · ...      │
└──────────────────────────────────────────┘
```

## What This Does

Deploys IAM roles and policies that enable CrowdStrike to perform automated security response actions in your AWS environment:
- **19 CDR Automated Response Actions** (enabled by default) - Detection-driven automatic threat response
- **62 Store Plugin Actions** (disabled by default) - Manual/workflow-driven SOAR actions

## Quick Start

### Fastest: Interactive Setup

```bash
./setup.sh
```

Prompts for your External ID, account IDs, and region — generates config and deploys in one step.

### Prerequisites

1. CrowdStrike Falcon subscription with Fusion SOAR capability
2. External ID from CrowdStrike Falcon console (Store > AWS SOAR Actions > Configure)
3. CrowdStrike Role ARN from CrowdStrike setup instructions (region-specific, see table below)
4. AWS account with CloudFormation StackSets enabled

### CrowdStrike Role ARN by Region

| Falcon Cloud | CrowdStrike Role ARN |
|---|---|
| **US-1** | `arn:aws:iam::292230061137:role/beta-crowdstrike-plugin-assume-role` |
| **US-2** | `arn:aws:iam::292230061137:role/mav-crowdstrike-plugin-assume-role` |
| **EU-1** | `arn:aws:iam::292230061137:role/lion-crowdstrike-plugin-assume-role` |
| **GOV-1** | `arn:aws-us-gov:iam::358431324613:role/eagle-crowdstrike-plugin-assume-role` |
| **GOV-2** | `arn:aws-us-gov:iam::142028973013:role/merlin-crowdstrike-plugin-assume-role` |

### Option 1: One-Click Deploy (AWS Console)

Click the **Launch Stack** button at the top of this page, then fill in:
- **ExternalId**: From CrowdStrike Store > AWS SOAR Actions > Configure
- **CrowdStrikeRoleArn**: Region-specific ARN (see table below)
- **AutomatedResponseRoleName**: `CrowdStrikeAutomatedResponse` (or custom)

### Option 2: Deploy via Makefile

```bash
# Deploy to specific accounts
make deploy-accounts ACCOUNTS=111111111111,222222222222

# Deploy to an Organizational Unit
make deploy-ou OUS=ou-xxxx-yyyyyyyy

# Use advanced parameters
make deploy-accounts ACCOUNTS=111111111111 PARAMS=cloudformation-stacksets/examples/parameters-advanced.json
```

### Option 3: Deploy via Script

```bash
cd cloudformation-stacksets/scripts
./deploy-stackset.sh -m accounts -p ../examples/parameters-basic.json -a "123456789012"
```

See `make help` for all available commands.

## Complete the Setup in CrowdStrike

After deployment:

1. Get the IAM Role ARN from CloudFormation Stack outputs
2. Log into CrowdStrike Falcon console
3. Go to **Store** > **AWS SOAR Actions** > **Configure**
4. Click **Add configuration**:
   - **Configuration Name**: `<account-id>-soar`
   - **Role ARN**: From CloudFormation output
   - **External ID**: Value used in parameters
5. Click **Save**

## SOAR Actions Available

### CDR Automated Response (19 actions - Default: Enabled)

Detection-driven actions that execute automatically when CrowdStrike detects threats:

**IAM Actions (6):**
- Update access key status (disable compromised keys)
- Apply deny policies to compromised users/roles
- Get instance profile roles
- Validate IAM roles
- Extract instance IDs from CloudTrail

**EC2 Actions (7):**
- Get/stop compromised instances
- Find instances and NAT gateways by IP
- Delete NAT gateways
- Make snapshots private
- Modify security group ingress rules

**SSM Actions (2):**
- Install Falcon agent
- Get task execution status

**Lambda Actions (1):**
- Throttle function concurrency

**S3 Actions (2):**
- Delete bucket replication
- Block public access

**EFS Actions (1):**
- Remove public access

### Store Plugin Actions (62 actions - Default: Disabled)

**IAM Management:** User lifecycle, Access keys, Policies, Roles, Security audit, Federation, Authentication (43 actions)

**EC2 Management:** Instance, Network interface, Security group, Volume operations (4 actions)

**GuardDuty, Lambda, S3, SNS, SQS, SSM, WAF, etc.** (15 additional actions)

See [granular template](cloudformation-stacksets/templates/crowdstrike-soar-actions-granular.yaml) for complete list.

## Parameter Files

**Basic** (`parameters-basic.json`): CDR automated response only
**Advanced** (`parameters-advanced.json`): CDR + common Store plugin actions

Edit these files to:
- Set your External ID
- Enable/disable specific actions
- Set permissions boundary (optional)
- Customize role name (optional)

## Testing Your Deployment

```bash
# Full test suite
make test

# Quick check — role exists and has policies
make test-quick

# Deployment status across accounts
make status
```

## Troubleshooting

### "Access Denied" in Fusion Workflows

| Symptom | Cause | Fix |
|---------|-------|-----|
| Action fails with AccessDenied | Required action not enabled | Enable the action in your parameters file and update the StackSet |
| Action fails for specific resource | Resource-level policy restriction | Check if a permissions boundary is blocking the action |
| All actions fail | STS policy not enabled | Ensure `EnableSTS=true` — this is required for all actions |

**How to find the exact denied API call:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --max-items 5 --query 'Events[*].CloudTrailEvent' --output text | jq '.errorCode'
```

### "Invalid External ID"

- External ID must match **exactly** between CloudFormation parameters and CrowdStrike Store configuration
- External ID is **case-sensitive**
- Copy-paste from the Falcon console to avoid typos
- If you rotated the External ID in CrowdStrike, update your StackSet parameters and redeploy

### "AssumeRole Failed"

- Verify Intermediate Role ARN matches what CrowdStrike provided
- Check that the SOAR role's trust policy includes the correct intermediate role ARN
- For **GovCloud**, contact CrowdStrike support for the GovCloud-specific intermediate role ARN
- Verify the External ID condition in the trust policy matches

**Debug trust policy:**
```bash
aws iam get-role --role-name CrowdStrikeAutomatedResponse \
  --query 'Role.AssumeRolePolicyDocument' --output json | jq .
```

### StackSet Deployment Failures

| Error | Cause | Fix |
|-------|-------|-----|
| `OUTDATED` status | Stack instance needs update | Run `make deploy-accounts` to update |
| Role name conflict | Role already exists in target account | Delete existing role or use a different `AutomatedResponseRoleName` |
| Permissions boundary not found | Boundary policy doesn't exist in target account | Create the boundary policy first, or remove the `PermissionsBoundaryArn` parameter |
| Service limit exceeded | Too many IAM roles (1000 max) | Clean up unused roles in the target account |
| Trusted access not enabled | StackSets can't deploy to org | Run: `aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com` |

### SOAR Workflows Not Triggering

- Verify the role is configured in **CrowdStrike Store** > **AWS SOAR Actions** > **Configure**
- Check that the **Configuration Name** matches the account where you expect actions to run
- Ensure the Fusion workflow is **enabled** and has the correct trigger condition
- Allow up to 15 minutes after initial configuration for the first action to appear in CloudTrail

### Template Validation Errors

```bash
# Lint templates locally
make validate

# Or validate against AWS API
aws cloudformation validate-template \
  --template-body file://cloudformation-stacksets/templates/crowdstrike-soar-actions-granular.yaml
```

## Security

- **Least Privilege**: Each action has minimal required permissions
- **External ID**: Prevents confused deputy problem
- **CloudTrail Logging**: All role assumptions logged
- **Permissions Boundaries**: Supported for enterprise compliance
- **12-hour session duration**: Balances security with long-running workflows

## Documentation

- [Full Deployment Guide](cloudformation-stacksets/README.md)
- [CrowdStrike Fusion SOAR Docs](https://falcon.crowdstrike.com/documentation/page/fusion-soar)
- [AWS SOAR Actions Store Plugin](https://falcon.crowdstrike.com/store)

## License

Apache 2.0

## Support

- CloudFormation templates: Open GitHub issue
- CrowdStrike Falcon Fusion SOAR: Contact CrowdStrike Support
