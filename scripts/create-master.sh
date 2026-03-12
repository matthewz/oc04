#!/bin/bash
set -e
set -x
# Arguments
MASTER_NAME="${1}"
MASTER_MEMORY="${2}"
MASTER_CPUS="${3}"
DISK_SIZE="${4}"
OUTPUT_FILE="${5}"
echo "=================================================="
echo "Creating Kubernetes Master Node"
echo "=================================================="
echo "Name: ${MASTER_NAME}"
echo "Memory: ${MASTER_MEMORY}"
echo "CPUs: ${MASTER_CPUS}"
echo "Disk: ${DISK_SIZE}"
echo "=================================================="
# Check if VM already exists
if multipass list | grep -q "${MASTER_NAME}"; then
  echo "⚠️  VM ${MASTER_NAME} already exists. Deleting..."
  multipass delete ${MASTER_NAME} --purge || true
  sleep 5
fi
# Create the VM
echo "" > ./launch_${MASTER_NAME}_out.txt
echo "🚀 Launching VM...${MASTER_NAME}"
(
multipass launch --name ${MASTER_NAME} \
  --memory ${MASTER_MEMORY} \
  --cpus ${MASTER_CPUS} \
  --disk ${DISK_SIZE} \
  22.04 \
  -v
) 1> ./launch_${MASTER_NAME}_out.txt 2>&1
#
#
# Wait for VM to boot and network to stabilize
echo "⏳ Waiting for VM to be ready..."
sleep 15
# Verify VM is running
if ! multipass list | grep -q "${MASTER_NAME}.*Running"; then
  echo "❌ Error: VM failed to start"
  exit 1
fi
# Get the VM's IP address
echo "🔍 Getting VM IP address..."
MASTER_IP=$(multipass info ${MASTER_NAME} --format json | \
  jq -r '.info["'${MASTER_NAME}'"].ipv4[0]')
if [ -z "${MASTER_IP}" ] || [ "${MASTER_IP}" = "null" ]; then
  echo "❌ Error: Failed to get IP address"
  exit 1
fi
echo "✅ Master IP: ${MASTER_IP}"
# Save IP to file
echo "${MASTER_IP}" > "${OUTPUT_FILE}"
echo "✅ Master node creation complete!"
echo "=================================================="
