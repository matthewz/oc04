#!/bin/bash
# Configures Vault after init — idempotent, safe to re-run
set -euo pipefail
VAULT_ADDR=$1
KEYS_FILE=$2
export VAULT_ADDR
export VAULT_TOKEN=$(cat $KEYS_FILE | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")
echo "⚙️  Enabling KV v2 secrets engine..."
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "   (already enabled)"
echo "⚙️  Enabling Kubernetes auth method..."
vault auth enable kubernetes 2>/dev/null || echo "   (already enabled)"
echo "⚙️  Writing openclaw policy..."
vault policy write openclaw-policy - <<EOF
path "secret/data/openclaw/*" {
  capabilities = ["read"]
}
EOF
echo "✅ Vault configured"
