#!/bin/bash
# Exit immediately if a command fails
set -e
# Assign arguments to readable variables
TYPE=$1          # master or worker
VM_NAME=$2       # e.g., k8s-master
MEMORY=$3        # e.g., 4G
CPUS=$4          # e.g., 2
DISK=$5          # e.g., 20G
IP_FILE_PATH=$6  # Path to save the IP (e.g., ./out/master-ip.txt)
echo "-----------------------------------------------------"
echo "Processing VM: $VM_NAME ($TYPE)"
echo "-----------------------------------------------------"
# 1. Check if the VM already exists to prevent errors on re-runs
if multipass list --format csv | grep -q "^$VM_NAME,"; then
    echo "Info: VM '$VM_NAME' already exists. Skipping launch."
else
    echo "Action: Launching $VM_NAME with ${CPUS} CPUs, ${MEMORY} RAM, and ${DISK} Disk..."
    
    # Launch the VM using the Ubuntu 22.04 LTS image (standard for K8s)
    multipass launch --name "$VM_NAME" \
                     --cpus "$CPUS" \
                     --mem "$MEMORY" \
                     --disk "$DISK" \
                     22.04
fi
# 2. THE BRAKE: Wait for the VM to be fully responsive
# This prevents 'Connection Refused' during the next Terraform step.
echo "Waiting for $VM_NAME to be internally ready (Cloud-Init)..."
MAX_RETRIES=30
RETRY_COUNT=0
until multipass exec "$VM_NAME" -- uname -a > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "Error: VM $VM_NAME failed to become ready after $MAX_RETRIES attempts."
        exit 1
    fi
    echo "   ...still waiting for $VM_NAME to wake up (Attempt $RETRY_COUNT/$MAX_RETRIES)..."
    sleep 3
done
echo "Success: $VM_NAME is responsive."
# 3. Capture the IP Address
# We use 'multipass info' and parse the IPv4 address
echo "Extracting IP address for $VM_NAME..."
VM_IP=$(multipass info "$VM_NAME" --format csv | grep "$VM_NAME" | cut -d',' -f3)
if [ -z "$VM_IP" ]; then
    echo "Error: Could not retrieve IP address for $VM_NAME"
    exit 1
fi
# 4. Save the IP to the specified file for Terraform to use later
echo "$VM_IP" > "$IP_FILE_PATH"
echo "Saved IP ($VM_IP) to $IP_FILE_PATH"
# 5. SRE Bonus: Show disk usage on the Mac host
echo "Current VM Status:"
multipass info "$VM_NAME" | grep -E "State|IPv4|Disk"
echo "-----------------------------------------------------"
