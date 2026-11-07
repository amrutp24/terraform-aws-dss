#!/usr/bin/env bash
# Read the admin API key the bootstrap wrote at boot, and save it to .apikey.
#
# This does both halves in one go. send-command returns a command id, not the
# key; the key only comes back from get-command-invocation, and conflating the
# two is an easy mistake to make by hand.
set -euo pipefail

cd "$(dirname "$0")"

# Both optional. Unset PROFILE uses whatever the AWS CLI would resolve on
# its own, and unset REGION falls back to the CLI default too, so this
# works unchanged in an environment that already has them configured.
# Exported rather than passed as flags: the AWS CLI honours both, and an
# empty bash array expanded under set -u is an error on bash 3.2, which
# macOS still ships.
[ -n "${PROFILE:-}" ] && export AWS_PROFILE="$PROFILE"
[ -n "${REGION:-}" ] && export AWS_DEFAULT_REGION="$REGION"
INSTANCE="${INSTANCE_ID:-$(terraform output -raw instance_id)}"
KEYPATH="$(terraform output -raw api_key_path 2>/dev/null || echo /var/lib/dataiku-terraform-key.json)"

echo "instance: $INSTANCE"
echo "reading:  $KEYPATH"

# DSS answers on its port before the bootstrap has written the key: it has to
# wait for the backend to accept dsscli first, which is a good half minute
# later. Waiting for the file on the host is the condition that matters, so
# the command does that waiting rather than this script guessing a delay.
CMD_ID="$(aws ssm send-command \
  --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"for i in \$(seq 1 60); do [ -s $KEYPATH ] && break; sleep 5; done; cat $KEYPATH\"]" \
  --timeout-seconds 600 \
  --query Command.CommandId --output text)"

echo "command:  $CMD_ID"

# SSM is asynchronous; the invocation is not readable the instant it is sent.
# The command itself may now wait up to five minutes for the key file, so give
# it longer than that before giving up.
for _ in $(seq 1 120); do
  STATUS="$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" --instance-id "$INSTANCE" \
    --query Status --output text 2>/dev/null || echo Pending)"
  case "$STATUS" in
    Success) break ;;
    Failed|Cancelled|TimedOut)
      echo "command $STATUS:" >&2
      aws ssm get-command-invocation \
        --command-id "$CMD_ID" --instance-id "$INSTANCE" \
        --query StandardErrorContent --output text >&2
      exit 1 ;;
  esac
  sleep 5
done
[ "$STATUS" = "Success" ] || { echo "command still $STATUS after 10 minutes" >&2; exit 1; }

aws ssm get-command-invocation \
  --command-id "$CMD_ID" --instance-id "$INSTANCE" \
  --query StandardOutputContent --output text \
| python -c '
import json, re, sys
raw = sys.stdin.read()
m = re.search(r"dkuaps-[A-Za-z0-9]+", raw)
if not m:
    sys.exit("no DSS key in the output; the bootstrap may not have written one yet")
open(".apikey", "w").write(m.group(0))
print("wrote .apikey: %d chars, starts %s" % (len(m.group(0)), m.group(0)[:7]))
'

# Prove it actually authenticates, rather than assuming.
HOST="$(terraform output -raw dss_url)"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -u "$(cat .apikey):" "$HOST/public/api/admin/users/")"
echo "auth check against $HOST: http=$CODE"
[ "$CODE" = "200" ] || { echo "the key did not authenticate" >&2; exit 1; }
