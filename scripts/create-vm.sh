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
# 1. Check if the VM already exists....and, then, deleting, if needed.
VM_EXISTS=$(multipass list --format csv | grep "^$VM_NAME," || true)
if [ -n "$VM_EXISTS" ]; then
   echo "Info: VM '$VM_NAME' already exists...deleting!"
   set -x
   multipass delete --purge "$VM_NAME" 
   set +x
fi
echo "Action: Launching $VM_NAME..."
(
set -x
multipass launch --name "$VM_NAME" \
                 --cpus "$CPUS" \
                 --memory "$MEMORY" \
                 --disk "$DISK" \
                 22.04
set +x
) \
1> launch_${VM_NAME}_out.txt \
2>&1
# 2. THE BRAKE: Wait for the VM to be fully responsive
# This prevents 'Connection Refused' during the next Terraform step.
echo "Waiting for $VM_NAME to be internally ready (Cloud-Init)..."
MAX_RETRIES=3
RETRY_COUNT=0
until multipass exec "$VM_NAME" -- uname -a 2> /dev/null
do
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
# FIX: Use awk instead of grep+cut for reliable, version-safe IP extraction.
# - NR>1 skips the header row entirely (no risk of matching "Name" column)
# - $1==VM_NAME does an exact column match instead of a loose grep
# - This is safe regardless of whether the VM name appears elsewhere in the output
echo "Extracting IP address for $VM_NAME..."
VM_IP=$(multipass info "$VM_NAME" --format csv | awk -F',' -v vm="$VM_NAME" 'NR>1 && $1==vm {print $3}')
# Validate the IP looks like an actual IP address (basic sanity check)
if [ -z "$VM_IP" ]; then
    echo "Error: Could not retrieve IP address for $VM_NAME — got empty result."
    echo "Current multipass info output:"
    multipass info "$VM_NAME" --format csv
    exit 1
fi
if ! echo "$VM_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Retrieved value '$VM_IP' does not look like a valid IP address."
    echo "Current multipass info output:"
    multipass info "$VM_NAME" --format csv
    exit 1
fi
# 4. Save the IP to the specified file for Terraform to use later
# Ensure the output directory exists defensively
mkdir -p "$(dirname "$IP_FILE_PATH")"
echo "$VM_IP" > "$IP_FILE_PATH"
echo "Saved IP ($VM_IP) to $IP_FILE_PATH"
# 5. Show VM status summary
echo "Current VM Status:"
multipass info "$VM_NAME" | grep -E "State|IPv4|Disk"
echo "-----------------------------------------------------"

