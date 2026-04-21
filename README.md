# CrowdStrike AWS SOAR Actions

CloudFormation templates for deploying CrowdStrike Falcon Fusion SOAR (Security Orchestration, Automation, and Response) actions to AWS with granular, action-level IAM permissions.

## What This Does

Deploys IAM roles and policies that enable CrowdStrike to perform automated security response actions in your AWS environment:
- **19 CDR Automated Response Actions** (enabled by default) - Detection-driven automatic threat response
- **62 Store Plugin Actions** (disabled by default) - Manual/workflow-driven SOAR actions

## Quick Start

### Prerequisites

1. CrowdStrike Falcon subscription with Fusion SOAR capability
2. External ID from CrowdStrike Falcon console (Store > AWS SOAR Actions > Configure)
3. AWS account with CloudFormation StackSets enabled
4. Intermediate Role ARN: `arn:aws:iam::YOUR_CS_ACCOUNT_ID:role/CrowdStrikeCSPMConnector`

### Option 1: Deploy via AWS Console (GUI)

1. **Log into AWS Console** in your management account
2. Go to **CloudFormation** > **StackSets** > **Create StackSet**
3. Choose **Service-managed permissions**
4. Upload template: `cloudformation-stacksets/templates/crowdstrike-soar-actions-granular.yaml`
5. **Configure Parameters:**
   - **ExternalId**: Get from CrowdStrike Store > AWS SOAR Actions > Configure
   - **IntermediateRoleArn**: `arn:aws:iam::YOUR_CS_ACCOUNT_ID:role/CrowdStrikeCSPMConnector`
   - **SOARRoleName**: `CrowdStrikeFusionSOARRole` (or custom)
   - Enable/disable specific actions as needed
6. **Deployment targets:**
   - Select accounts or entire OUs
   - Enable automatic deployment for new accounts
7. **Regions:** Select `us-east-1` (IAM is global)
8. Click **Submit**

### Option 2: Deploy via Command Line

**Single Account:**
```bash
cd cloudformation-stacksets/scripts
./deploy-stackset.sh -m accounts -p ../examples/parameters-basic.json -a "123456789012"
```

**AWS Organization (OU):**
```bash
cd cloudformation-stacksets/scripts
./deploy-stackset.sh -m ou -p ../examples/parameters-basic.json -o "ou-xxxx-yyyyyyyy"
```

**Multiple Accounts:**
```bash
cd cloudformation-stacksets/scripts
./deploy-stackset.sh -m accounts -p ../examples/parameters-advanced.json -a "111111111111,222222222222"
```

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

### Quick Test (2 minutes)
```bash
# Verify role created
aws iam get-role --role-name CrowdStrikeFusionSOARRole

# List attached policies
aws iam list-role-policies --role-name CrowdStrikeFusionSOARRole
```

### Automated Testing
```bash
# Run comprehensive test suite
./scripts/test-soar-deployment.sh

# Or run quick validation only
./scripts/test-soar-deployment.sh --quick
```

### Manual Verification
```bash
# Check CloudTrail for role assumptions
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=CrowdStrikeFusionSOARRole \
  --max-items 10
```

## Common Issues

**"Access Denied" in Fusion workflows**
- Enable the required action in your parameters file
- Update the StackSet
- Check CloudTrail for specific denied API call

**"Invalid External ID"**
- Verify External ID matches between CloudFormation parameters and CrowdStrike Store
- External ID is case-sensitive

**"AssumeRole Failed"**
- Verify Intermediate Role ARN is correct: `arn:aws:iam::YOUR_CS_ACCOUNT_ID:role/CrowdStrikeCSPMConnector`
- For GovCloud, contact CrowdStrike support for GovCloud-specific ARN

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
