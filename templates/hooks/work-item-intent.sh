#!/bin/bash
# Work Item Intent Hook (UserPromptSubmit)
# Routes plain-language requests to create a work item through /create-work-item,
# so "log a bug for the export 500" gets the same prior-art check, title prefix,
# AC field, proposed points, and draft approval as typing the command.
#
# Never blocks. On a match it prints a note that Claude Code adds to the
# prompt's context; the note is conditional, so a false positive ("add a
# feature flag") costs a few tokens and is ignored.

# Read the hook input from stdin
INPUT=$(cat)

MATCH=$(echo "$INPUT" | python3 -c "
import sys, json, re
try:
    prompt = json.load(sys.stdin).get('prompt', '').strip()
except Exception:
    sys.exit(0)

# Slash commands run their own flow — /create-work-item is already running,
# and work items other commands create (Tasks, child stories) follow theirs.
if prompt.startswith('/'):
    sys.exit(0)

verb = r'\b(create|make|add|file|log|open|raise|write\s+up|submit|draft|put\s+in|enter)\b'
noun = (r'\b(work\s*items?|tickets?|bugs?|user\s+stor(y|ies)|stor(y|ies)|'
        r'features?(?!\s+(flags?|toggles?|branch(es)?))|hot\s*fix(es)?|backlog\s+items?|pbis?)\b')

if re.search(verb + r'.{0,40}?' + noun, prompt, re.IGNORECASE | re.DOTALL):
    print('match')
" 2>/dev/null)

if [ "$MATCH" = "match" ]; then
    echo "Work item request check: if the user is asking to create an Azure DevOps work item (Bug, User Story, Feature, or Hot Fix), run /create-work-item now with the Skill tool, passing their request as the arguments. Do not create it with a direct wit_work_item_write call. If /create-work-item is already running in this conversation, or this prompt is not a request to create a work item, ignore this note."
fi

exit 0
