# CloudFormation StackSets Deployment for AWS Organizations

This directory contains CloudFormation templates and scripts for deploying CrowdStrike Falcon Fusion SOAR Actions IAM roles across multiple AWS accounts in your organization using CloudFormation StackSets.

## Overview

CloudFormation StackSets allows you to deploy the SOAR IAM role to:
- **Multiple AWS accounts** simultaneously
- **Entire Organizational Units (OUs)** with automatic deployment to new accounts
- **Multiple regions** in each account

This is the recommended approach for enterprise deployments with AWS Organizations.

## Why Use StackSets?

### Single Account vs Multi-Account Deployment

| Aspect | Single Account (Manual) | CloudFormation StackSets |
|--------|------------------------|--------------------------|
| **Target** | One account at a time | Multiple accounts/entire OUs |
| **Automation** | Manual per-account deployment | Organization-wide automation |
| **New Accounts** | Manual deployment required | Automatic (with OU deployment) |
| **Management** | Individual stack per account | Centralized StackSet management |
| **Updates** | Update each account separately | Single update to all accounts |
| **Best For** | 1-5 accounts | 6+ accounts or AWS Organizations |

**Recommendation:**
- **1-5 accounts**: Deploy individually using AWS Console
- **6+ accounts or AWS Organization**: Use CloudFormation StackSets

## Prerequisites

### 1. AWS Organizations Setup
- AWS Organizations must be enabled in your management account
- Trusted access must be enabled for CloudFormation StackSets

Enable trusted access:
```bash
aws organizations enable-aws-service-access \
    --service-principal member.org.stacksets.cloudformation.amazonaws.com
```

### 2. IAM Permissions

The user/role deploying StackSets needs these permissions in the management account:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "organizations:ListAccounts",
        "organizations:DescribeOrganization",
        "organizations:ListOrganizationalUnitsForParent",
        "organizations:ListRoots"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. StackSet Execution Role

For SERVICE_MANAGED permission model (recommended), CloudFormation automatically creates the execution role in target accounts. No manual setup required.

For SELF_MANAGED permission model, you need to create `AWSCloudFormationStackSetExecutionRole` in each target account. See [AWS Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-prereqs-self-managed.html).

### 4. CrowdStrike External ID

Obtain the external ID from your CrowdStrike Falcon console before deployment:
1. Log into Falcon console
2. Go to **CrowdStrike Store** > **AWS SOAR Actions**
3. Click **Configure** > **View setup instructions**
4. Copy the **External ID**

## Directory Structure

```
cloudformation-stacksets/
├── templates/
│   └── crowdstrike-soar-actions.yaml    # CloudFormation template
├── examples/
│   ├── parameters-basic.json             # Basic configuration (default actions)
│   └── parameters-advanced.json          # Advanced configuration (custom actions)
├── scripts/
│   ├── deploy-stackset.sh                # Deployment automation script
│   └── cleanup-stackset.sh               # Cleanup script
└── README.md                             # This file
```

## Quick Start

### Option 1: Deploy via AWS Console (Recommended for first-time users)

#### Step 1: Access CloudFormation StackSets

1. Log into AWS Console in your **management account**
2. Navigate to **CloudFormation** service
3. In left sidebar, click **StackSets**
4. Click **Create StackSet** button

#### Step 2: Choose Template

1. **Permissions**: Select **Service-managed permissions**
2. **Specify template**: Choose **Upload a template file**
3. Click **Choose file** and select: `templates/crowdstrike-soar-actions-granular.yaml`
4. Click **Next**

#### Step 3: Configure StackSet Details

1. **StackSet name**: `CrowdStrike-SOAR-Actions`
2. **Description**: (optional) "CrowdStrike Fusion SOAR Actions IAM roles"
3. Click **Next**

#### Step 4: Configure Parameters

**Required Parameters:**
- **ExternalId**:
  1. Go to CrowdStrike Falcon console
  2. Navigate to **Store** > **AWS SOAR Actions** > **Configure**
  3. Copy the **External ID** shown
- **IntermediateRoleArn**: `arn:aws:iam::YOUR_CS_ACCOUNT_ID:role/CrowdStrikeCSPMConnector`
- **SOARRoleName**: `CrowdStrikeFusionSOARRole` (or choose custom name)

**Optional - Enable/Disable Actions:**
- **CDR Actions**: Default is `true` (19 automated response actions)
- **Store Plugin Actions**: Default is `false` (62 manual/workflow actions)
- Change any action to `true` or `false` as needed

**Optional - Advanced:**
- **PermissionsBoundaryArn**: (if required by your org) `arn:aws:iam::123456789012:policy/YourBoundary`

Click **Next**

#### Step 5: Configure Deployment Options

**Automatic deployment:**
- ✅ Enable **Automatic deployment**
- ✅ Select **Delete stacks** for account removal behavior

**Deployment targets:**
- Choose one:
  - **Deploy to organization**: Select root or specific OUs
  - **Deploy to accounts**: Enter comma-separated account IDs

**Regions:**
- Select **us-east-1** only (IAM is global service)

Click **Next**

#### Step 6: Review and Create

1. Review all settings
2. ✅ Check **I acknowledge that AWS CloudFormation might create IAM resources**
3. Click **Submit**

#### Step 7: Monitor Deployment

1. StackSet operations tab shows progress
2. Wait for status: **SUCCEEDED**
3. Check **Stack instances** tab to verify deployment to each account

Deployment typically takes 2-5 minutes per account.

### Option 2: Deploy via Command Line

1. **Edit parameters file**:
```bash
cp examples/parameters-basic.json my-parameters.json
# Edit my-parameters.json and set your ExternalId
```

2. **Deploy**:
```bash
cd scripts
./deploy-stackset.sh \
    -m accounts \
    -p ../my-parameters.json \
    -a "111111111111,222222222222,333333333333"
```

### Option 2: Deploy to Organizational Unit

Deploy to all accounts in an OU (and automatically deploy to new accounts added to the OU):

```bash
cd scripts
./deploy-stackset.sh \
    -m ou \
    -p ../examples/parameters-basic.json \
    -o "ou-xxxx-yyyyyyyy"
```

### Option 3: Deploy to Multiple Regions

```bash
cd scripts
./deploy-stackset.sh \
    -m accounts \
    -p ../examples/parameters-advanced.json \
    -a "111111111111,222222222222" \
    -r "us-east-1,us-west-2,eu-west-1"
```

## Deployment Script Options

```
Usage: deploy-stackset.sh [OPTIONS]

OPTIONS:
    -m, --mode MODE              Deployment mode: 'accounts' or 'ou' (required)
    -p, --parameters FILE        Path to parameters JSON file (required)
    -a, --accounts "ID1,ID2"     Comma-separated list of AWS account IDs
    -o, --ous "OU1,OU2"          Comma-separated list of OU IDs
    -r, --regions "REGION1,..."  Comma-separated list of regions (default: us-east-1)
    -n, --name NAME              StackSet name (default: CrowdStrike-SOAR-Actions)
    -h, --help                   Display help message
```

## Parameter Files Explained

### Basic Configuration (parameters-basic.json)

Enables only the most common SOAR actions:
- EC2 (instance isolation, security group management)
- GuardDuty (findings management)
- IAM (user/role management)
- S3 (object quarantine, bucket policies)
- STS (required for role assumption)

### Advanced Configuration (parameters-advanced.json)

Enables additional security automation actions:
- All basic actions
- Secrets Manager (secret rotation)
- SSM (command execution)
- WAF (rule management)
- Config (compliance evaluation)
- Lambda (function management)
- CloudWatch Logs (log querying)
- SNS (notifications)
- Network Firewall (policy updates)

Plus sets a permissions boundary for enterprise compliance.

## Customizing Parameters

Create your own parameters file:

```json
[
  {
    "ParameterKey": "ExternalId",
    "ParameterValue": "your-actual-external-id"
  },
  {
    "ParameterKey": "IntermediateRoleArn",
    "ParameterValue": "arn:aws:iam::YOUR_CS_ACCOUNT_ID:role/CrowdStrikeCSPMConnector"
  },
  {
    "ParameterKey": "SOARRoleName",
    "ParameterValue": "CrowdStrikeFusionSOARRole"
  },
  {
    "ParameterKey": "EnableEC2",
    "ParameterValue": "true"
  },
  {
    "ParameterKey": "PermissionsBoundaryArn",
    "ParameterValue": "arn:aws:iam::123456789012:policy/YourBoundary"
  }
]
```

## Monitoring Deployment

### View StackSet Operations

```bash
aws cloudformation list-stack-set-operations \
    --stack-set-name CrowdStrike-SOAR-Actions
```

### List Stack Instances

```bash
aws cloudformation list-stack-instances \
    --stack-set-name CrowdStrike-SOAR-Actions
```

### Check Specific Account Status

```bash
aws cloudformation describe-stack-instance \
    --stack-set-name CrowdStrike-SOAR-Actions \
    --stack-instance-account 111111111111 \
    --stack-instance-region us-east-1
```

## Post-Deployment: CrowdStrike Store Configuration

After successful deployment, configure CrowdStrike Store for each account:

### Automated Approach (Recommended)

Create a script to retrieve role ARNs from all accounts:

```bash
#!/bin/bash
ACCOUNTS="111111111111 222222222222 333333333333"

for account in $ACCOUNTS; do
    echo "Account: $account"
    echo "Role ARN: arn:aws:iam::${account}:role/CrowdStrikeFusionSOARRole"
    echo
done
```

### Manual Approach

For each account:
1. Log into **CrowdStrike Falcon console**
2. Go to **CrowdStrike Store** > **AWS SOAR Actions**
3. Click **Configure** > **Add configuration**
4. Enter:
   - **Configuration Name**: `<account-id>-soar`
   - **Role ARN**: `arn:aws:iam::<account-id>:role/CrowdStrikeFusionSOARRole`
   - **External ID**: (same value used during deployment)
5. Click **Save configuration**

## Updating Existing StackSet

To update the template or parameters:

```bash
cd scripts
./deploy-stackset.sh \
    -m accounts \
    -p ../my-updated-parameters.json \
    -a "111111111111,222222222222"
```

The script will detect the existing StackSet and prompt you to update it.

Or manually update:

```bash
aws cloudformation update-stack-set \
    --stack-set-name CrowdStrike-SOAR-Actions \
    --template-body file://templates/crowdstrike-soar-actions.yaml \
    --parameters file://examples/parameters-advanced.json \
    --capabilities CAPABILITY_NAMED_IAM
```

## Adding New Accounts

### Automatic (OU Deployment)

If you deployed to an OU with auto-deployment enabled, new accounts added to that OU will automatically receive the stack.

### Manual (Account Deployment)

```bash
aws cloudformation create-stack-instances \
    --stack-set-name CrowdStrike-SOAR-Actions \
    --accounts 444444444444 \
    --regions us-east-1
```

## Removing Deployment

Use the cleanup script to remove all instances and the StackSet:

```bash
cd scripts
./cleanup-stackset.sh
```

This will:
1. Delete all stack instances from all accounts
2. Delete the StackSet
3. Remove IAM roles from all target accounts

**Warning**: This is irreversible. You'll need to reconfigure CrowdStrike Store if you redeploy.

## Troubleshooting

### Error: "Service-managed permissions not enabled"

Enable trusted access:
```bash
aws organizations enable-aws-service-access \
    --service-principal member.org.stacksets.cloudformation.amazonaws.com
```

### Error: "Access Denied" when creating StackSet

Ensure you're running from the **management account** or a **delegated administrator** account for StackSets.

### Stack Creation Failed in Some Accounts

Check the specific error:
```bash
aws cloudformation describe-stack-set-operation \
    --stack-set-name CrowdStrike-SOAR-Actions \
    --operation-id <operation-id>
```

Common issues:
- **Role name conflict**: A role with that name already exists
- **Permissions boundary**: The specified boundary doesn't exist in the target account
- **Service limit**: IAM role limit reached (default: 1000 roles per account)

### StackSet Operation Stuck

Check operation status:
```bash
aws cloudformation describe-stack-set-operation \
    --stack-set-name CrowdStrike-SOAR-Actions \
    --operation-id <operation-id>
```

Cancel if needed:
```bash
aws cloudformation stop-stack-set-operation \
    --stack-set-name CrowdStrike-SOAR-Actions \
    --operation-id <operation-id>
```

## Validation

After deployment, verify the role exists in target accounts:

### From Management Account

```bash
# Assume role in target account
aws sts assume-role \
    --role-arn arn:aws:iam::111111111111:role/OrganizationAccountAccessRole \
    --role-session-name validation

# Then check role (using assumed credentials)
aws iam get-role --role-name CrowdStrikeFusionSOARRole
```

### From Target Account

```bash
aws iam get-role --role-name CrowdStrikeFusionSOARRole
aws iam list-role-policies --role-name CrowdStrikeFusionSOARRole
```

### Test SOAR Workflow

1. Create a test Fusion workflow in CrowdStrike Falcon
2. Add an AWS action (e.g., EC2 Describe Instance)
3. Select one of your configured accounts
4. Run the workflow
5. Verify CloudTrail logs show role assumption from CrowdStrike

## Best Practices

1. **Use Organizational Units**: Deploy to OUs rather than individual accounts for automatic coverage of new accounts

2. **Enable Auto-Deployment**: Ensure new accounts in your OU automatically receive the role

3. **Single Region**: Deploy to only one region (e.g., `us-east-1`) since IAM is a global service

4. **Version Control**: Store your parameters files in version control

5. **Tagging**: Use consistent tags for cost tracking and governance

6. **Testing**: Test in a non-production OU first before deploying to production

7. **Documentation**: Document which SOAR actions are enabled and why

8. **Least Privilege**: Only enable the SOAR actions your security team actually uses

## Cost Considerations

- **CloudFormation StackSets**: No additional charge
- **IAM Roles**: No charge
- **CrowdStrike SOAR**: May have licensing implications based on number of accounts; consult with CrowdStrike

## Support

For issues with:
- **CloudFormation StackSets**: AWS Support
- **Template/Scripts**: Open a GitHub issue
- **CrowdStrike Falcon Fusion SOAR**: CrowdStrike Support

## Additional Resources

- [AWS CloudFormation StackSets Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [CrowdStrike Falcon Fusion SOAR Documentation](https://falcon.crowdstrike.com/documentation/page/fusion-soar)
- [Terraform Module Version](../../README.md)
