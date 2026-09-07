#!/bin/bash
# Sensitive Data Output Blocker Hook (PostToolUse - Bash, Read, Grep, Playwright, MCP DB tools)
# Scans tool output for sensitive PII that may have been returned by broad database
# queries, file reads of seed/dump data, grep results, or a rendered browser page.
# Exit code 2 = BLOCK (prevents the output from being used).
#
# Two pattern sets, chosen by tool:
#   * Database / file / grep tools -> match sensitive field NAMES. A query or a seed
#     file that names TIN or SSN at all is already returning data it shouldn't.
#   * Playwright (mcp__playwright__*) -> match a field name only when followed by
#     something VALUE-shaped. A rendered screen legitimately shows "SSN:" as a form
#     label, and blocking on the label alone would make every such screen untestable
#     and send /qa into a retry loop.

# Read the tool result from stdin
INPUT=$(cat)

# Extract the tool name so the pattern set can be chosen below
TOOL=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_name', ''))
except:
    pass
" 2>/dev/null)

# Extract output from any tool type (Bash stdout, Read content, Grep results, MCP results)
OUTPUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool = data.get('tool_name', '')
    result = data.get('tool_result', '')

    # Handle different result shapes
    if isinstance(result, dict):
        # Bash tool: check stdout
        text = result.get('stdout', '')
        # MCP/other tools: check content or stringify the whole result
        if not text:
            text = result.get('content', '')
        if not text:
            text = json.dumps(result)
    elif isinstance(result, str):
        text = result
    else:
        text = str(result)

    print(text)
except:
    pass
" 2>/dev/null)

if [ -z "$OUTPUT" ]; then
    exit 0
fi

FIELDS='TIN|Tin|TaxId|TaxIdentificationNumber|EIN|SSN|SocialSecurityNumber|EncryptedTin|EncryptedSSN|EncryptedTaxId|BankAccountNumber|AccountNumber|RoutingNumber'

if [[ "$TOOL" == mcp__playwright__* ]]; then
    # A rendered page: block only when a value actually accompanies the field name.
    SENSITIVE_PATTERNS=(
        # JSON body surfaced through the browser: "SSN": "123-45-6789"
        "\"($FIELDS)\"\s*:\s*\"?[0-9]"
        # Rendered value: SSN: 123-45-6789 / TIN = 12-3456789 / Account #: ****1234.
        # Requires at least one real digit, so a fully masked "***-**-****" is allowed
        # through -- that carries no data, and /qa needs to verify masking works.
        "($FIELDS)\s*#?\s*[:=]\s*[\"']?[*Xx-]{0,8}[0-9][0-9*Xx-]{2,}"
        # A bare SSN or EIN anywhere on the page, label or not
        '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b'
        '\b[0-9]{2}-[0-9]{7}\b'
    )
    BLOCK_MSG="BLOCKED: Browser output contains a sensitive value (SSN, TIN, bank account, etc.)"
    BLOCK_HELP="Do not retry this snapshot. Record the screen as 'BLOCKED — protected fields on screen,
manual QA required', test only its structure/validation/navigation, and move on.
Never transcribe a protected field's value into a report or a work item comment."
else
    # Database / file / grep output: the field NAME appearing at all means PII was returned.
    SENSITIVE_PATTERNS=(
        # JSON/MongoDB style: "TIN": or 'TIN':
        "\"($FIELDS)\"\s*:"
        # C# property style: .TIN = or .TaxId =
        "\.($FIELDS)\s*="
        # YAML/config style: TIN: (start of line or after whitespace)
        "(^|\s)($FIELDS):\s"
    )
    BLOCK_MSG="BLOCKED: Output contains sensitive PII fields (TIN, SSN, bank account, etc.)"
    BLOCK_HELP="For database queries: use an explicit inclusion projection listing only non-sensitive fields.
For code searches: avoid reading seed data, test fixtures, or dump files containing PII.
If you need to work with this data, use the application UI instead."
fi

for PATTERN in "${SENSITIVE_PATTERNS[@]}"; do
    if echo "$OUTPUT" | grep -qE "$PATTERN"; then
        echo "$BLOCK_MSG"
        echo "$BLOCK_HELP"
        exit 2
    fi
done

exit 0
