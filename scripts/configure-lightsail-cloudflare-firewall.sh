#!/bin/bash

# Restrict public HTTP/HTTPS ingress to Cloudflare while preserving SSH access.
# Cloudflare's published ranges are fetched at runtime so the firewall does not
# depend on a stale copy committed to this repository.

set -euo pipefail

INSTANCE_NAME="${1:-selfhosted-stack}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PORTS_FILE=$(mktemp)
trap 'rm -f "$PORTS_FILE"' EXIT

mapfile -t CLOUDFLARE_IPV4 < <(curl -fsS https://www.cloudflare.com/ips-v4/)
mapfile -t CLOUDFLARE_IPV6 < <(curl -fsS https://www.cloudflare.com/ips-v6/)

if [ "${#CLOUDFLARE_IPV4[@]}" -eq 0 ] || [ "${#CLOUDFLARE_IPV6[@]}" -eq 0 ]; then
    echo "ERROR: Cloudflare returned an empty IP range list" >&2
    exit 1
fi

IPV4_JSON=$(printf '%s\n' "${CLOUDFLARE_IPV4[@]}" | jq -R . | jq -s .)
IPV6_JSON=$(printf '%s\n' "${CLOUDFLARE_IPV6[@]}" | jq -R . | jq -s .)

jq -n \
    --arg instanceName "$INSTANCE_NAME" \
    --argjson cloudflareIpv4 "$IPV4_JSON" \
    --argjson cloudflareIpv6 "$IPV6_JSON" \
    '{
        instanceName: $instanceName,
        portInfos: [
            {
                fromPort: 22,
                toPort: 22,
                protocol: "tcp",
                cidrs: ["0.0.0.0/0"],
                ipv6Cidrs: ["::/0"]
            },
            {
                fromPort: 80,
                toPort: 80,
                protocol: "tcp",
                cidrs: $cloudflareIpv4,
                ipv6Cidrs: $cloudflareIpv6
            },
            {
                fromPort: 443,
                toPort: 443,
                protocol: "tcp",
                cidrs: $cloudflareIpv4,
                ipv6Cidrs: $cloudflareIpv6
            }
        ]
    }' > "$PORTS_FILE"

echo "Restricting ${INSTANCE_NAME} HTTP/HTTPS ingress to Cloudflare ranges..."
aws lightsail put-instance-public-ports \
    --region "$AWS_REGION" \
    --cli-input-json "file://${PORTS_FILE}" \
    --query 'operation.{id:id,status:status,errorCode:errorCode,errorDetails:errorDetails}' \
    --output table

aws lightsail get-instance-port-states \
    --instance-name "$INSTANCE_NAME" \
    --region "$AWS_REGION" \
    --output table
