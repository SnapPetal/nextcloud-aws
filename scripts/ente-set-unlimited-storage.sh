#!/bin/bash
set -euo pipefail

# Sets Ente Photos storage/validity to the self-hosted "no limit" values for
# every account returned by the Ente admin CLI.

API_ENDPOINT="${ENTE_API_ENDPOINT:-https://photos-api.thonbecker.biz}"
CONFIG_DIR="${ENTE_CLI_CONFIG_DIR:-$HOME/.ente}"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
DRY_RUN=false

usage() {
    cat <<'USAGE'
Usage: scripts/ente-set-unlimited-storage.sh -a ADMIN_EMAIL [--dry-run]

Environment:
  ENTE_API_ENDPOINT   Museum API endpoint. Defaults to https://photos-api.thonbecker.biz
  ENTE_CLI_CONFIG_DIR Ente CLI config directory. Defaults to ~/.ente

Before running:
  1. Install the Ente CLI.
  2. Ensure ADMIN_EMAIL's user ID is listed in ente/museum.yaml under internal.admins.
  3. Run: ente account add
USAGE
}

ADMIN_EMAIL=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -a|--admin-email)
            ADMIN_EMAIL="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$ADMIN_EMAIL" ]; then
    echo "Error: ADMIN_EMAIL is required" >&2
    usage >&2
    exit 1
fi

if ! command -v ente >/dev/null 2>&1; then
    echo "Error: ente CLI is not installed or not on PATH" >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
endpoint:
  api: $API_ENDPOINT
EOF

echo "Using Ente API endpoint: $API_ENDPOINT"
echo "Listing Ente users with admin: $ADMIN_EMAIL"

USER_EMAILS="$(
    ente admin list-users -a "$ADMIN_EMAIL" \
        | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[^[:space:]<>"]+@[^[:space:]<>"]+\.[^[:space:]<>",;]+$/) {
                        gsub(/[",;]$/, "", $i)
                        print $i
                    }
                }
            }
        ' \
        | sort -u
)"

if [ -z "$USER_EMAILS" ]; then
    echo "Error: no user emails found in ente admin list-users output" >&2
    exit 1
fi

while IFS= read -r USER_EMAIL; do
    [ -n "$USER_EMAIL" ] || continue
    if [ "$DRY_RUN" = true ]; then
        echo "Would update $USER_EMAIL"
    else
        echo "Updating $USER_EMAIL"
        ente admin update-subscription \
            -a "$ADMIN_EMAIL" \
            -u "$USER_EMAIL" \
            --no-limit True
    fi
done <<< "$USER_EMAILS"

echo "Done"
