#!/bin/bash
set -euo pipefail
VAULT_ADDR=$1
echo "🔑 Running vault operator init..."
#vault operator init \
#  -key-shares=3 \
#  -key-threshold=2 \
#  -format=json > .vault_keys.json
curl -s -X PUT -d '{"secret_shares": 5, "secret_threshold": 3}' \
  "${VAULT_ADDR}/v1/sys/init" > .vault_keys.json
echo "✅ Keys saved to .vault_keys.json"
echo "⚠️  Back this file up somewhere safe and NEVER commit it to git!"
# OR if using the Vault CLI:
# vault operator init -format=json > .vault_keys.json
