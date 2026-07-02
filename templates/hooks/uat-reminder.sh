#!/bin/bash
# UAT Reminder Hook
# Fires on the Stop event to remind about UAT after feature implementation
#
# This checks if recent conversation context suggests a feature was being
# implemented and reminds the user to run UAT before marking it complete.

echo "Reminder: If you just completed a feature implementation, run UAT before marking it done."
echo "Ask Claude to generate a UAT checklist from the work item's acceptance criteria."
