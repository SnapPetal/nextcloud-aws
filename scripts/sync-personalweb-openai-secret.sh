#!/usr/bin/env bash
# Sync PersonalWeb runtime secrets from AWS Secrets Manager into the local compose .env file.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_FILE="${ENV_FILE:-.env}"
SECRET_ID="${PERSONAL_OPENAI_SECRET_ID:-personalweb/openai-api-key}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

AWS_REGION="${PERSONAL_AWS_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_ACCESS_KEY_ID="${PERSONAL_AWS_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
export AWS_SECRET_ACCESS_KEY="${PERSONAL_AWS_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"

if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "Missing AWS credentials. Set PERSONAL_AWS_ACCESS_KEY_ID and PERSONAL_AWS_SECRET_ACCESS_KEY in $ENV_FILE." >&2
  exit 1
fi

openai_key="$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --query SecretString \
  --output text \
  --region "$AWS_REGION")"

if [[ -z "$openai_key" || "$openai_key" == "None" ]]; then
  echo "Secret $SECRET_ID did not return a usable value." >&2
  exit 1
fi

set_env_var() {
  local name="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  touch "$ENV_FILE"
  grep -v "^${name}=" "$ENV_FILE" > "$tmp" || true
  printf "%s=%s\n" "$name" "$value" >> "$tmp"
  mv "$tmp" "$ENV_FILE"
}

set_env_var PERSONAL_OPENAI_API_KEY "$openai_key"
set_env_var PERSONAL_OPENAI_CHAT_MODEL "${PERSONAL_OPENAI_CHAT_MODEL:-gpt-4o}"
set_env_var PERSONAL_OPENAI_TRIVIA_MODEL "${PERSONAL_OPENAI_TRIVIA_MODEL:-gpt-4o-mini}"
set_env_var PERSONAL_OPENAI_EMBEDDING_MODEL "${PERSONAL_OPENAI_EMBEDDING_MODEL:-text-embedding-3-small}"
set_env_var PERSONAL_OPENAI_EMBEDDING_DIMENSIONS "${PERSONAL_OPENAI_EMBEDDING_DIMENSIONS:-1024}"
set_env_var PERSONAL_OPENAI_IMAGE_MODEL "${PERSONAL_OPENAI_IMAGE_MODEL:-dall-e-3}"

chmod 600 "$ENV_FILE"
echo "Synced PersonalWeb OpenAI secret into $ENV_FILE"
