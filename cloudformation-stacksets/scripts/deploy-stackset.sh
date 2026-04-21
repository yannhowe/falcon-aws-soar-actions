#!/bin/bash
#
# deploy-stackset.sh
# Deploy CrowdStrike SOAR Actions to multiple AWS accounts via CloudFormation StackSets
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate IAM permissions for StackSets operations
# - Organizations must be enabled if deploying to OUs
# - StackSet execution role configured in target accounts
#

set -e

# Configuration
STACKSET_NAME="CrowdStrike-SOAR-Actions"
TEMPLATE_PATH="../templates/crowdstrike-soar-actions.yaml"
PARAMETERS_FILE=""
DEPLOYMENT_MODE=""
TARGET_ACCOUNTS=""
TARGET_OUS=""
REGIONS="us-east-1"
OPERATION_PREFERENCES="FailureTolerancePercentage=0,MaxConcurrentPercentage=100"
CAPABILITIES="CAPABILITY_NAMED_IAM"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy CrowdStrike SOAR Actions IAM roles to multiple AWS accounts via StackSets.

OPTIONS:
    -m, --mode MODE              Deployment mode: 'accounts' or 'ou' (required)
    -p, --parameters FILE        Path to parameters JSON file (required)
    -a, --accounts "ID1,ID2"     Comma-separated list of AWS account IDs (required if mode=accounts)
    -o, --ous "OU1,OU2"          Comma-separated list of Organizational Unit IDs (required if mode=ou)
    -r, --regions "REGION1,..."  Comma-separated list of regions (default: us-east-1)
    -n, --name NAME              StackSet name (default: CrowdStrike-SOAR-Actions)
    -h, --help                   Display this help message

EXAMPLES:
    # Deploy to specific accounts
    $0 -m accounts -p ../examples/parameters-basic.json -a "111111111111,222222222222"

    # Deploy to all accounts in an OU
    $0 -m ou -p ../examples/parameters-advanced.json -o "ou-xxxx-yyyyyyyy"

    # Deploy to multiple accounts in multiple regions
    $0 -m accounts -p ../examples/parameters-basic.json -a "111111111111,222222222222" -r "us-east-1,us-west-2"

PREREQUISITES:
    1. Configure AWS CLI with appropriate credentials
    2. Enable trusted access for CloudFormation StackSets in Organizations (for OU deployments)
    3. Create StackSet execution role in target accounts:
       Role Name: AWSCloudFormationStackSetExecutionRole
       Trust Policy: Management account or delegated administrator account

    For more information, see:
    https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-getting-started.html

EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi

    # Check template exists
    if [ ! -f "$TEMPLATE_PATH" ]; then
        log_error "Template file not found: $TEMPLATE_PATH"
        exit 1
    fi

    # Check parameters file exists
    if [ ! -f "$PARAMETERS_FILE" ]; then
        log_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi

    # Validate AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

validate_template() {
    log_info "Validating CloudFormation template..."

    if aws cloudformation validate-template --template-body file://"$TEMPLATE_PATH" &> /dev/null; then
        log_success "Template validation passed"
    else
        log_error "Template validation failed"
        exit 1
    fi
}

create_stackset() {
    log_info "Creating StackSet: $STACKSET_NAME"

    CALLER_IDENTITY=$(aws sts get-caller-identity --query 'Account' --output text)

    aws cloudformation create-stack-set \
        --stack-set-name "$STACKSET_NAME" \
        --template-body file://"$TEMPLATE_PATH" \
        --parameters file://"$PARAMETERS_FILE" \
        --capabilities "$CAPABILITIES" \
        --permission-model SERVICE_MANAGED \
        --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
        --description "CrowdStrike Falcon Fusion SOAR Actions IAM roles for multi-account deployment" \
        --tags Key=ManagedBy,Value=CloudFormation Key=Purpose,Value=CrowdStrike-SOAR

    log_success "StackSet created: $STACKSET_NAME"
}

update_stackset() {
    log_info "Updating existing StackSet: $STACKSET_NAME"

    aws cloudformation update-stack-set \
        --stack-set-name "$STACKSET_NAME" \
        --template-body file://"$TEMPLATE_PATH" \
        --parameters file://"$PARAMETERS_FILE" \
        --capabilities "$CAPABILITIES"

    log_success "StackSet updated: $STACKSET_NAME"
}

deploy_to_accounts() {
    log_info "Deploying StackSet instances to accounts: $TARGET_ACCOUNTS"

    IFS=',' read -ra ACCOUNT_ARRAY <<< "$TARGET_ACCOUNTS"
    IFS=',' read -ra REGION_ARRAY <<< "$REGIONS"

    OPERATION_ID=$(aws cloudformation create-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --accounts "${ACCOUNT_ARRAY[@]}" \
        --regions "${REGION_ARRAY[@]}" \
        --operation-preferences "$OPERATION_PREFERENCES" \
        --query 'OperationId' \
        --output text)

    log_info "StackSet operation started with ID: $OPERATION_ID"
    monitor_operation "$OPERATION_ID"
}

deploy_to_ous() {
    log_info "Deploying StackSet instances to OUs: $TARGET_OUS"

    IFS=',' read -ra OU_ARRAY <<< "$TARGET_OUS"
    IFS=',' read -ra REGION_ARRAY <<< "$REGIONS"

    OPERATION_ID=$(aws cloudformation create-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --deployment-targets OrganizationalUnitIds="${OU_ARRAY[@]}" \
        --regions "${REGION_ARRAY[@]}" \
        --operation-preferences "$OPERATION_PREFERENCES" \
        --query 'OperationId' \
        --output text)

    log_info "StackSet operation started with ID: $OPERATION_ID"
    monitor_operation "$OPERATION_ID"
}

monitor_operation() {
    local operation_id=$1
    log_info "Monitoring StackSet operation: $operation_id"

    while true; do
        STATUS=$(aws cloudformation describe-stack-set-operation \
            --stack-set-name "$STACKSET_NAME" \
            --operation-id "$operation_id" \
            --query 'StackSetOperation.Status' \
            --output text)

        if [ "$STATUS" == "SUCCEEDED" ]; then
            log_success "StackSet operation completed successfully"
            break
        elif [ "$STATUS" == "FAILED" ] || [ "$STATUS" == "STOPPED" ]; then
            log_error "StackSet operation failed with status: $STATUS"
            exit 1
        else
            log_info "Operation status: $STATUS - Waiting..."
            sleep 10
        fi
    done
}

list_stack_instances() {
    log_info "Listing deployed stack instances..."

    aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --query 'Summaries[*].[Account,Region,Status]' \
        --output table
}

# Main script
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                DEPLOYMENT_MODE="$2"
                shift 2
                ;;
            -p|--parameters)
                PARAMETERS_FILE="$2"
                shift 2
                ;;
            -a|--accounts)
                TARGET_ACCOUNTS="$2"
                shift 2
                ;;
            -o|--ous)
                TARGET_OUS="$2"
                shift 2
                ;;
            -r|--regions)
                REGIONS="$2"
                shift 2
                ;;
            -n|--name)
                STACKSET_NAME="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$DEPLOYMENT_MODE" ] || [ -z "$PARAMETERS_FILE" ]; then
        log_error "Missing required arguments"
        print_usage
        exit 1
    fi

    if [ "$DEPLOYMENT_MODE" == "accounts" ] && [ -z "$TARGET_ACCOUNTS" ]; then
        log_error "Account IDs required for 'accounts' deployment mode"
        exit 1
    fi

    if [ "$DEPLOYMENT_MODE" == "ou" ] && [ -z "$TARGET_OUS" ]; then
        log_error "Organizational Unit IDs required for 'ou' deployment mode"
        exit 1
    fi

    # Execute deployment
    check_prerequisites
    validate_template

    # Check if StackSet exists
    if aws cloudformation describe-stack-set --stack-set-name "$STACKSET_NAME" &> /dev/null; then
        log_warning "StackSet already exists"
        read -p "Do you want to update it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_stackset
        fi
    else
        create_stackset
    fi

    # Deploy instances
    if [ "$DEPLOYMENT_MODE" == "accounts" ]; then
        deploy_to_accounts
    else
        deploy_to_ous
    fi

    # Show results
    list_stack_instances

    log_success "Deployment complete!"
    echo
    log_info "Next steps:"
    echo "  1. Log in to the CrowdStrike Falcon console"
    echo "  2. Navigate to CrowdStrike Store > AWS SOAR Actions"
    echo "  3. Add a configuration for each AWS account with the role ARN"
    echo "  4. Test SOAR workflows in each account"
}

# Run main function
main "$@"
