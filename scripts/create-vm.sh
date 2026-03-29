#!/bin/bash
set -e
# Arguments
MODE="${1}"           # master or worker
VM_NAME="${2}"
VM_MEMORY="${3}"
VM_CPUS="${4}"
DISK_SIZE="${5}"
OUTPUT_FILE="${6:-}"  # Optional 6th argument
echo "=================================================="
echo "🏗️  Creating Kubernetes ${MODE}: ${VM_NAME}"
echo "=================================================="
# 1. Cleanup existing VM
if multipass list | grep -q "${VM_NAME}"; then
  echo "⚠️  VM ${VM_NAME} exists. Purging for fresh install..."
  multipass delete "${VM_NAME}" --purge || true
  # Give Multipass a moment to release the file locks
  sleep 5
fi
# 2. Launch VM
echo "🚀 Launching Multipass VM (${VM_MEMORY} RAM, ${VM_CPUS} CPU)..."
# We use --cloud-init to ensure basic networking is ready faster
multipass launch --name "${VM_NAME}" \
  --memory "${VM_MEMORY}" \
  --cpus "${VM_CPUS}" \
  --disk "${DISK_SIZE}" \
  22.04 > "./launch_${VM_NAME}_out.txt" 2>&1
# 3. Active Wait for IP
echo "⏳ Waiting for VM to resolve IP address..."
VM_IP=""
for i in {1..20}; do
    # Fetching IP via multipass info
    VM_IP=$(multipass info "${VM_NAME}" --format json | jq -r ".info[\"${VM_NAME}\"].ipv4[0] // empty")
    
    if [[ -n "$VM_IP" && "$VM_IP" != "null" ]]; then
        break
    fi
    echo "..."
    sleep 3
done
if [ -z "$VM_IP" ]; then
  echo "❌ Error: VM started but failed to get an IP address."
  exit 1
fi
echo "✅ ${MODE} IP: ${VM_IP}"
# 4. Save IP to file if requested
if [ -n "$OUTPUT_FILE" ]; then
    # Ensure the directory exists before writing
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    echo "${VM_IP}" > "${OUTPUT_FILE}"
    echo "📝 IP saved to ${OUTPUT_FILE}"
fi
echo "✅ ${MODE} node creation complete!"
echo "=================================================="
