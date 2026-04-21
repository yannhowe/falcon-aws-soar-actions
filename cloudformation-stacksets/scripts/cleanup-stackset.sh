#!/bin/bash
#
# cleanup-stackset.sh
# Remove CrowdStrike SOAR Actions StackSet and all instances
#

set -e

STACKSET_NAME="CrowdStrike-SOAR-Actions"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo
log_warning "This will delete the StackSet '$STACKSET_NAME' and ALL instances in ALL accounts!"
echo
read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
echo

if [[ ! $REPLY == "yes" ]]; then
    log_info "Aborted"
    exit 0
fi

# Check if StackSet exists
if ! aws cloudformation describe-stack-set --stack-set-name "$STACKSET_NAME" &> /dev/null; then
    log_error "StackSet does not exist: $STACKSET_NAME"
    exit 1
fi

# Get all stack instances
log_info "Retrieving stack instances..."
INSTANCES=$(aws cloudformation list-stack-instances \
    --stack-set-name "$STACKSET_NAME" \
    --query 'Summaries[*].[Account,Region]' \
    --output text)

if [ -z "$INSTANCES" ]; then
    log_info "No stack instances found"
else
    # Extract unique accounts and regions
    ACCOUNTS=$(echo "$INSTANCES" | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
    REGIONS=$(echo "$INSTANCES" | awk '{print $2}' | sort -u | tr '\n' ',' | sed 's/,$//')

    log_info "Deleting stack instances from accounts: $ACCOUNTS"
    log_info "Regions: $REGIONS"

    IFS=',' read -ra ACCOUNT_ARRAY <<< "$ACCOUNTS"
    IFS=',' read -ra REGION_ARRAY <<< "$REGIONS"

    OPERATION_ID=$(aws cloudformation delete-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --accounts "${ACCOUNT_ARRAY[@]}" \
        --regions "${REGION_ARRAY[@]}" \
        --no-retain-stacks \
        --query 'OperationId' \
        --output text)

    log_info "Deletion operation started: $OPERATION_ID"
    log_info "Waiting for instances to be deleted..."

    # Wait for deletion to complete
    while true; do
        STATUS=$(aws cloudformation describe-stack-set-operation \
            --stack-set-name "$STACKSET_NAME" \
            --operation-id "$OPERATION_ID" \
            --query 'StackSetOperation.Status' \
            --output text)

        if [ "$STATUS" == "SUCCEEDED" ]; then
            log_success "Stack instances deleted successfully"
            break
        elif [ "$STATUS" == "FAILED" ] || [ "$STATUS" == "STOPPED" ]; then
            log_error "Stack instance deletion failed: $STATUS"
            exit 1
        else
            log_info "Deletion status: $STATUS - Waiting..."
            sleep 10
        fi
    done
fi

# Delete the StackSet
log_info "Deleting StackSet: $STACKSET_NAME"
aws cloudformation delete-stack-set --stack-set-name "$STACKSET_NAME"

log_success "StackSet deleted successfully"
echo
log_info "Remember to remove the configurations from CrowdStrike Store"
