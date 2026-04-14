#!/bin/bash
# Unseals vault using saved keys
# Needs 2 of 3 keys (matching your key-threshold=2)
set -euo pipefail
VAULT_ADDR=$1
KEYS_FILE=$2
export VAULT_ADDR
echo "🔓 Unsealing Vault..."
vault operator unseal $(cat $KEYS_FILE | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
vault operator unseal $(cat $KEYS_FILE | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][1])")
echo "✅ Vault unsealed"
