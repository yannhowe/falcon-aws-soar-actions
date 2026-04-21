#!/bin/bash
#
# setup.sh — Interactive setup for CrowdStrike Falcon AWS SOAR Actions
# Prompts for configuration, generates a parameters file, and deploys.
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARAMS_FILE="$SCRIPT_DIR/my-parameters.json"
TEMPLATE_DIR="$SCRIPT_DIR/cloudformation-stacksets"

# ─── Banner ──────────────────────────────────────────────────────────
echo
echo -e "${BOLD}CrowdStrike Falcon AWS SOAR Actions — Setup${NC}"
echo "─────────────────────────────────────────────"
echo

# ─── Prerequisites ───────────────────────────────────────────────────
log_info "Checking prerequisites..."

if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not found. Install it: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit 1
fi

if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS credentials not configured. Run: aws configure"
    exit 1
fi

CALLER_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
CALLER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
log_success "Authenticated as $CALLER_ARN (account $CALLER_ACCOUNT)"
echo

# ─── Template choice ────────────────────────────────────────────────
echo -e "${BOLD}Step 1: Choose template${NC}"
echo "  1) Granular (recommended) — per-action enable/disable toggles"
echo "  2) Standard — grouped by AWS service"
echo
read -rp "Template [1]: " TEMPLATE_CHOICE
TEMPLATE_CHOICE="${TEMPLATE_CHOICE:-1}"

if [ "$TEMPLATE_CHOICE" == "1" ]; then
    TEMPLATE_FILE="$TEMPLATE_DIR/templates/crowdstrike-soar-actions-granular.yaml"
    TEMPLATE_NAME="granular"
else
    TEMPLATE_FILE="$TEMPLATE_DIR/templates/crowdstrike-soar-actions.yaml"
    TEMPLATE_NAME="standard"
fi
log_success "Using $TEMPLATE_NAME template"
echo

# ─── External ID ────────────────────────────────────────────────────
echo -e "${BOLD}Step 2: CrowdStrike External ID${NC}"
echo "  Find this in: Falcon Console → Store → AWS SOAR Actions → Configure"
echo
read -rp "External ID: " EXTERNAL_ID

if [ -z "$EXTERNAL_ID" ]; then
    log_error "External ID is required"
    exit 1
fi
echo

# ─── Intermediate Role ARN ──────────────────────────────────────────
echo -e "${BOLD}Step 3: CrowdStrike Role ARN${NC}"
echo "  Find this in the same CrowdStrike setup instructions."
echo "  This is region-specific:"
echo "    US-1: arn:aws:iam::292230061137:role/beta-crowdstrike-plugin-assume-role"
echo "    US-2: arn:aws:iam::292230061137:role/mav-crowdstrike-plugin-assume-role"
echo "    EU-1: arn:aws:iam::292230061137:role/lion-crowdstrike-plugin-assume-role"
echo
read -rp "CrowdStrike Role ARN: " CROWDSTRIKE_ROLE_ARN

if [ -z "$CROWDSTRIKE_ROLE_ARN" ]; then
    log_error "CrowdStrike Role ARN is required"
    exit 1
fi
echo

# ─── Role name ──────────────────────────────────────────────────────
echo -e "${BOLD}Step 4: Automated Response Role Name${NC}"
read -rp "Role name [CrowdStrikeAutomatedResponse]: " ROLE_NAME
ROLE_NAME="${ROLE_NAME:-CrowdStrikeAutomatedResponse}"
echo

# ─── Deployment mode ────────────────────────────────────────────────
echo -e "${BOLD}Step 5: Deployment target${NC}"
echo "  1) Specific AWS account(s)"
echo "  2) Organizational Unit (OU)"
echo "  3) Generate parameters only (no deploy)"
echo
read -rp "Deployment target [1]: " DEPLOY_MODE
DEPLOY_MODE="${DEPLOY_MODE:-1}"

TARGET_ACCOUNTS=""
TARGET_OUS=""
REGIONS="us-east-1"

if [ "$DEPLOY_MODE" == "1" ]; then
    echo
    read -rp "AWS account IDs (comma-separated): " TARGET_ACCOUNTS
    if [ -z "$TARGET_ACCOUNTS" ]; then
        log_error "At least one account ID is required"
        exit 1
    fi
elif [ "$DEPLOY_MODE" == "2" ]; then
    echo
    read -rp "OU IDs (comma-separated, e.g. ou-xxxx-yyyyyyyy): " TARGET_OUS
    if [ -z "$TARGET_OUS" ]; then
        log_error "At least one OU ID is required"
        exit 1
    fi
fi

echo
read -rp "AWS region [us-east-1]: " REGIONS_INPUT
REGIONS="${REGIONS_INPUT:-us-east-1}"
echo

# ─── Generate parameters file ───────────────────────────────────────
log_info "Generating parameters file: $PARAMS_FILE"

cat > "$PARAMS_FILE" << EOF
[
  {
    "ParameterKey": "ExternalId",
    "ParameterValue": "$EXTERNAL_ID"
  },
  {
    "ParameterKey": "CrowdStrikeRoleArn",
    "ParameterValue": "$CROWDSTRIKE_ROLE_ARN"
  },
  {
    "ParameterKey": "AutomatedResponseRoleName",
    "ParameterValue": "$ROLE_NAME"
  },
  {
    "ParameterKey": "PermissionsBoundaryArn",
    "ParameterValue": ""
  }
]
EOF

log_success "Parameters saved to my-parameters.json"
echo

# ─── Summary ────────────────────────────────────────────────────────
echo -e "${BOLD}Summary${NC}"
echo "─────────────────────────────────────────────"
echo "  Template:           $TEMPLATE_NAME"
echo "  External ID:        ${EXTERNAL_ID:0:8}..."
echo "  CrowdStrike Role:   $CROWDSTRIKE_ROLE_ARN"
echo "  Role Name:          $ROLE_NAME"
echo "  Region:             $REGIONS"
if [ "$DEPLOY_MODE" == "1" ]; then
    echo "  Target accounts:    $TARGET_ACCOUNTS"
elif [ "$DEPLOY_MODE" == "2" ]; then
    echo "  Target OUs:         $TARGET_OUS"
else
    echo "  Deploy:             Parameters only (no deploy)"
fi
echo "─────────────────────────────────────────────"
echo

if [ "$DEPLOY_MODE" == "3" ]; then
    log_success "Setup complete! Parameters saved to my-parameters.json"
    echo
    echo "To deploy later:"
    echo "  make deploy-accounts ACCOUNTS=111111111111 PARAMS=my-parameters.json"
    echo "  # or"
    echo "  make deploy-ou OUS=ou-xxxx-yyyyyyyy PARAMS=my-parameters.json"
    exit 0
fi

read -rp "Deploy now? (y/n) [y]: " CONFIRM
CONFIRM="${CONFIRM:-y}"

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    log_info "Skipped deployment. To deploy later:"
    echo "  make deploy-accounts ACCOUNTS=$TARGET_ACCOUNTS PARAMS=my-parameters.json"
    exit 0
fi

# ─── Deploy ─────────────────────────────────────────────────────────
echo
if [ "$DEPLOY_MODE" == "1" ]; then
    cd "$TEMPLATE_DIR/scripts"
    ./deploy-stackset.sh -m accounts -p "$PARAMS_FILE" -a "$TARGET_ACCOUNTS" -r "$REGIONS"
elif [ "$DEPLOY_MODE" == "2" ]; then
    cd "$TEMPLATE_DIR/scripts"
    ./deploy-stackset.sh -m ou -p "$PARAMS_FILE" -o "$TARGET_OUS" -r "$REGIONS"
fi

echo
log_success "Deployment complete!"
echo
echo "Next steps:"
echo "  1. Log in to CrowdStrike Falcon console"
echo "  2. Go to Store → AWS SOAR Actions → Configure"
echo "  3. Add configuration for each account with the Role ARN from CloudFormation outputs"
echo "  4. Run 'make test' to verify the deployment"
echo
