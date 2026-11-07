#!/usr/bin/env bash
# Copy the Community licence off the running instance into SSM Parameter
# Store, so a rebuild can read it instead of asking you to register again.
#
# Run this while the current instance is still up. Nothing is printed: the
# licence goes from the instance to Parameter Store and this only reports
# sizes and names.
#
# The licence does travel through SSM command output, which is readable by
# anyone with ssm:GetCommandInvocation and is kept for 30 days. If that is
# not acceptable, do it interactively instead:
#
#   aws ssm start-session --target <instance-id>
#   sudo cat <data_dir>/config/license.json                  # copy it
#   aws ssm put-parameter --name /dss/license --type SecureString --value '<paste>'
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash rewrites any argument that looks like a POSIX path before a native
# Windows program sees it, so "/dss/license" reaches aws.exe as
# "C:/Program Files/Git/dss/license". GetParameter tolerates that and answers
# ParameterNotFound, which hides it; PutParameter rejects it with "Parameter
# name must be a fully qualified name". Nothing here wants that conversion:
# the only other path passed is relative.
export MSYS_NO_PATHCONV=1

# PROFILE and REGION are optional: unset means the AWS CLI resolves them
# as it normally would. PARAM is where the licence is stored, and has to
# match the license_ssm_parameter you pass to the module.
PARAM="${PARAM:-/dss/license}"
# Exported rather than passed as flags: the AWS CLI honours both, and an
# empty bash array expanded under set -u is an error on bash 3.2, which
# macOS still ships.
[ -n "${PROFILE:-}" ] && export AWS_PROFILE="$PROFILE"
[ -n "${REGION:-}" ] && export AWS_DEFAULT_REGION="$REGION"
INSTANCE="${INSTANCE_ID:-$(terraform output -raw instance_id)}"
# Derived from the module's data_dir output rather than assumed, since
# data_dir is a variable.
DATA_DIR="${DATA_DIR:-$(terraform output -raw data_dir 2>/dev/null || echo /data/dataiku/dss_data)}"
LICENSE_PATH="$DATA_DIR/config/license.json"

echo "instance:  $INSTANCE"
echo "reading:   $LICENSE_PATH"
echo "parameter: $PARAM"

CMD_ID="$(aws ssm send-command \
  --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"sudo cat $LICENSE_PATH\"]" \
  --query Command.CommandId --output text)"

for _ in $(seq 1 40); do
  STATUS="$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" --instance-id "$INSTANCE" \
    --query Status --output text 2>/dev/null || echo Pending)"
  case "$STATUS" in
    Success) break ;;
    Failed|Cancelled|TimedOut)
      echo "reading the licence $STATUS" >&2
      aws ssm get-command-invocation --command-id "$CMD_ID" \
        --instance-id "$INSTANCE" \
        --query StandardErrorContent --output text >&2
      exit 1 ;;
  esac
  sleep 3
done
[ "${STATUS:-}" = "Success" ] || { echo "timed out waiting for the read" >&2; exit 1; }

# Straight into a temporary file and then into Parameter Store. The value is
# never echoed, and the file is removed on exit however this ends.
#
# Deliberately not mktemp. On Git Bash mktemp returns a path like
# /tmp/tmp.XXXX, which the AWS CLI cannot open because it is a native Windows
# binary and resolves /tmp against the current drive root. A file beside this
# script is a real path to every program involved. It is gitignored.
TMP=".license.tmp"
trap 'rm -f "$TMP"' EXIT
: > "$TMP"
chmod 600 "$TMP" 2>/dev/null || true
aws ssm get-command-invocation \
  --command-id "$CMD_ID" --instance-id "$INSTANCE" \
  --query StandardOutputContent --output text > "$TMP"

python - "$TMP" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit("what came back is not JSON, so it is not the licence")
expected = {"content", "r1Pub", "r1PubSig", "r1Sig"}
missing = expected - set(doc)
if missing:
    sys.exit("missing expected licence fields: %s" % sorted(missing))
print("licence looks right: %d bytes, keys %s" % (len(raw), sorted(doc)))
PY

aws ssm put-parameter \
  --name "$PARAM" \
  --type SecureString \
  --description "DSS Community licence, read by the instance at boot" \
  --value "file://$TMP" \
  --overwrite \
  --query Version --output text | sed 's/^/parameter version: /'

echo "stored. Nothing was printed, and the temporary copy is gone."
