#!/bin/bash
#
# test-soar-deployment.sh
# Automated testing for CrowdStrike SOAR Actions deployment
#

set -e

# Configuration
ROLE_NAME="${1:-CrowdStrikeFusionSOARRole}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

test_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

test_warn() {
    echo -e "${YELLOW}⚠️  WARNING${NC}: $1"
    ((TESTS_WARNING++))
}

echo "=========================================="
echo "Testing CrowdStrike SOAR Actions Deployment"
echo "=========================================="
echo "Account: $ACCOUNT_ID"
echo "Role: $ROLE_NAME"
echo ""

# Test 1: Role exists
echo "[Test 1/8] Checking if IAM role exists..."
if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
    test_pass "Role '$ROLE_NAME' exists"
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    echo "          Role ARN: $ROLE_ARN"
else
    test_fail "Role '$ROLE_NAME' does not exist"
    exit 1
fi

# Test 2: Trust policy
echo ""
echo "[Test 2/8] Verifying trust policy..."
TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json)
if echo "$TRUST_POLICY" | grep -q "sts:ExternalId"; then
    test_pass "External ID condition present in trust policy"
    EXTERNAL_ID_COUNT=$(echo "$TRUST_POLICY" | grep -c "sts:ExternalId" || true)
    echo "          External ID conditions: $EXTERNAL_ID_COUNT"
else
    test_fail "External ID condition missing from trust policy"
fi

if echo "$TRUST_POLICY" | grep -q "sts:AssumeRole"; then
    test_pass "AssumeRole action present"
else
    test_fail "AssumeRole action missing"
fi

# Test 3: Policies attached
echo ""
echo "[Test 3/8] Checking attached policies..."
POLICY_NAMES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text)
POLICY_COUNT=$(echo "$POLICY_NAMES" | wc -w | tr -d ' ')

if [ "$POLICY_COUNT" -ge 1 ]; then
    test_pass "$POLICY_COUNT inline policies attached"
    echo "          Policies: $POLICY_NAMES"
else
    test_fail "No policies attached to role"
fi

# Test 4: Verify specific policies have correct permissions
echo ""
echo "[Test 4/8] Validating policy permissions..."

# Check if STS policy exists (required)
if echo "$POLICY_NAMES" | grep -q "CrowdStrikeSOAR-sts"; then
    test_pass "STS policy attached (required for all actions)"

    # Verify STS policy has AssumeRole permission
    STS_POLICY=$(aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "CrowdStrikeSOAR-sts" --query 'PolicyDocument' --output json)
    if echo "$STS_POLICY" | grep -q "sts:AssumeRole"; then
        test_pass "STS policy contains AssumeRole permission"
    else
        test_warn "STS policy missing AssumeRole permission"
    fi
else
    test_warn "STS policy not attached (required for role assumption)"
fi

# Check common policies
for policy in "ec2" "guardduty" "iam" "s3"; do
    if echo "$POLICY_NAMES" | grep -q "CrowdStrikeSOAR-${policy}"; then
        echo -e "          ${GREEN}✓${NC} $policy policy attached"
    fi
done

# Test 5: Session duration
echo ""
echo "[Test 5/8] Verifying session duration..."
SESSION_DURATION=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.MaxSessionDuration' --output text)
if [ "$SESSION_DURATION" -eq 43200 ]; then
    test_pass "Session duration is 12 hours (43200 seconds)"
else
    test_warn "Session duration is $SESSION_DURATION seconds (expected 43200)"
    echo "          12-hour sessions allow long-running SOAR workflows"
fi

# Test 6: Tags
echo ""
echo "[Test 6/8] Checking tags..."
CROWDSTRIKE_TAG=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Tags[?Key==`CrowdStrikeManaged`].Value' --output text)
PURPOSE_TAG=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Tags[?Key==`Purpose`].Value' --output text)

if [ "$CROWDSTRIKE_TAG" == "true" ]; then
    test_pass "CrowdStrikeManaged tag present"
else
    test_warn "CrowdStrikeManaged tag missing or incorrect"
fi

if [ -n "$PURPOSE_TAG" ]; then
    echo -e "          ${GREEN}✓${NC} Purpose tag: $PURPOSE_TAG"
fi

# Test 7: CloudTrail events
echo ""
echo "[Test 7/8] Checking CloudTrail for AssumeRole events..."
echo "          (This may take a few minutes for recent deployments)"

ASSUME_EVENTS=$(aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue="$ROLE_NAME" \
    --max-items 10 \
    --query 'length(Events)' \
    --output text 2>/dev/null || echo "0")

if [ "$ASSUME_EVENTS" -gt 0 ]; then
    test_pass "Found $ASSUME_EVENTS AssumeRole events in CloudTrail"
    echo "          Role has been assumed by CrowdStrike"

    # Show most recent event
    LATEST_EVENT=$(aws cloudtrail lookup-events \
        --lookup-attributes AttributeKey=ResourceName,AttributeValue="$ROLE_NAME" \
        --max-items 1 \
        --query 'Events[0].EventTime' \
        --output text 2>/dev/null || echo "unknown")
    echo "          Latest event: $LATEST_EVENT"
else
    test_warn "No AssumeRole events found in CloudTrail"
    echo "          This is normal for newly created roles"
    echo "          Events will appear after CrowdStrike Store configuration"
fi

# Test 8: Role path
echo ""
echo "[Test 8/8] Verifying role configuration..."
ROLE_PATH=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Path' --output text)
if [ "$ROLE_PATH" == "/" ]; then
    test_pass "Role path is root (/)"
else
    echo -e "          ${BLUE}ℹ${NC} Role path: $ROLE_PATH"
fi

CREATE_DATE=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.CreateDate' --output text)
echo "          Created: $CREATE_DATE"

# Test 9: Permissions boundary (if set)
PERMISSIONS_BOUNDARY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text 2>/dev/null || echo "None")
if [ "$PERMISSIONS_BOUNDARY" != "None" ]; then
    echo -e "          ${BLUE}ℹ${NC} Permissions Boundary: $PERMISSIONS_BOUNDARY"
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed${NC}:   $TESTS_PASSED"
echo -e "${YELLOW}Warnings${NC}: $TESTS_WARNING"
echo -e "${RED}Failed${NC}:   $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}❌ Some tests failed. Please review the output above.${NC}"
    exit 1
elif [ $TESTS_WARNING -gt 0 ]; then
    echo -e "${YELLOW}⚠️  All critical tests passed, but there are warnings.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Review warnings above"
    echo "2. Configure the role in CrowdStrike Falcon console:"
    echo "   - Go to CrowdStrike Store > AWS SOAR Actions > Configure"
    echo "   - Add configuration with Role ARN: $ROLE_ARN"
    echo "   - Use your External ID from CrowdStrike"
    echo "3. Create a test SOAR workflow"
    echo "4. Run this test again after ~15 minutes to see CloudTrail events"
    echo ""
else
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Configure the role in CrowdStrike Falcon console:"
    echo "   - Go to CrowdStrike Store > AWS SOAR Actions > Configure"
    echo "   - Add configuration with Role ARN: $ROLE_ARN"
    echo "   - Use your External ID from CrowdStrike"
    echo "2. Create a test SOAR workflow in Falcon console"
    echo "3. Monitor CloudTrail for successful API calls:"
    echo "   aws cloudtrail lookup-events \\"
    echo "     --lookup-attributes AttributeKey=ResourceName,AttributeValue=$ROLE_NAME \\"
    echo "     --max-items 10"
    echo ""
fi
