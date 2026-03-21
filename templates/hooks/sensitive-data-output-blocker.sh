#!/bin/bash
# Sensitive Data Output Blocker Hook (PostToolUse - Bash)
# Scans command output for sensitive PII field names that may have been
# returned by broad database queries (e.g., find() without a projection).
# Exit code 2 = BLOCK (prevents the output from being used).

# Read the tool result from stdin
INPUT=$(cat)

# Extract the stdout from the tool result
OUTPUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Only check Bash results that look like they came from mongo
    tool = data.get('tool_name', '')
    stdout = data.get('tool_result', {}).get('stdout', '')
    if not stdout:
        stdout = str(data.get('tool_result', ''))
    print(stdout)
except:
    pass
" 2>/dev/null)

if [ -z "$OUTPUT" ]; then
    exit 0
fi

# Check if output contains sensitive field names as keys (indicating PII was returned)
# These patterns match MongoDB/JSON document field names in output
SENSITIVE_PATTERN='"(TIN|Tin|TaxId|TaxIdentificationNumber|EIN|SSN|SocialSecurityNumber|EncryptedTin|EncryptedSSN|EncryptedTaxId|BankAccountNumber|AccountNumber|RoutingNumber)"\s*:'

if echo "$OUTPUT" | grep -qE "$SENSITIVE_PATTERN"; then
    echo "BLOCKED: Command output contains sensitive PII fields (TIN, SSN, bank account, etc.)"
    echo "The query returned documents with sensitive fields. Use an explicit inclusion projection"
    echo "that lists only the non-sensitive fields you need."
    echo "If you need to work with this data, use the application UI instead."
    exit 2
fi

exit 0
