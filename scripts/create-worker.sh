#!/bin/bash
set -e
# Arguments
WORKER_NAME="${1}"
WORKER_MEMORY="${2}"
WORKER_CPUS="${3}"
DISK_SIZE="${4}"
OUTPUT_FILE="${5}"
echo "=================================================="
echo "Creating Kubernetes Worker Node"
echo "=================================================="
echo "Name: ${WORKER_NAME}"
echo "Memory: ${WORKER_MEMORY}"
echo "CPUs: ${WORKER_CPUS}"
echo "Disk: ${DISK_SIZE}"
echo "=================================================="
# Check if VM already exists
if multipass list | grep -q "${WORKER_NAME}"; then
  echo "⚠️  VM ${WORKER_NAME} already exists. Deleting..."
  multipass delete ${WORKER_NAME} --purge || true
  sleep 5
fi
# Create the VM
echo "🚀 Launching VM...${WORKER_NAME}"
echo "" > ./launch_${WORKER_NAME}_out.txt
(
multipass launch --name ${WORKER_NAME} \
  --memory ${WORKER_MEMORY} \
  --cpus ${WORKER_CPUS} \
  --disk ${DISK_SIZE} \
  22.04 \
  -v
) 1> ./launch_${WORKER_NAME}_out.txt 2>&1
# Wait for VM to boot and network to stabilize
echo "⏳ Waiting for VM to be ready..."
sleep 15
# Verify VM is running
if ! multipass list | grep -q "${WORKER_NAME}.*Running"; then
  echo "❌ Error: VM failed to start"
  exit 1
fi
# Get the VM's IP address
echo "🔍 Getting VM IP address..."
WORKER_IP=$(multipass info ${WORKER_NAME} --format json | \
  jq -r '.info["'${WORKER_NAME}'"].ipv4[0]')
if [ -z "${WORKER_IP}" ] || [ "${WORKER_IP}" = "null" ]; then
  echo "❌ Error: Failed to get IP address"
  exit 1
fi
echo "✅ Worker IP: ${WORKER_IP}"
# Save IP to file
echo "${WORKER_IP}" > "${OUTPUT_FILE}"
echo "✅ Worker node creation complete!"
echo "=================================================="
