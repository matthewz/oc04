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

IMAGE_TO_USE="24.04"

if [ -n "$K8S_GOLDEN_IMAGE" ]; then
    if [ -f "$K8S_GOLDEN_IMAGE" ]; then
        echo "🌟 Found Golden Image: $K8S_GOLDEN_IMAGE"
        # Multipass requires an absolute path for local images
        IMAGE_TO_USE=$(realpath "$K8S_GOLDEN_IMAGE")
    else
        echo "⚠️  K8S_GOLDEN_IMAGE was set but file not found at: $K8S_GOLDEN_IMAGE"
        echo "   Falling back to default Ubuntu 24.04..."
    fi
fi

echo "-----------------------------------------------------"
echo "Processing VM: $VM_NAME ($TYPE)"
echo "-----------------------------------------------------"

# 1. Get the raw info from Multipass
VM_INFO=$(multipass info "$VM_NAME" --format yaml 2>/dev/null || true)
# 2. DECISION LOGIC: Does it exist?
if [ -z "$VM_INFO" ] || [ "$VM_INFO" == "null" ]; then
    echo "🆕 VM '$VM_NAME' does not exist. Proceeding to launch..."
    SKIP_LAUNCH=false
else
    echo "🔍 VM '$VM_NAME' already exists. Verifying specs..."
    # --- THE PARSING ---
    # Extract CPU - look for cpu_count followed by digits
    CURRENT_CPUS=$(echo "$VM_INFO" | grep "cpu_count" | tr -dc '0-9')
    
    # Extract Memory (finds the first large number of 7-12 digits in the memory block)
    #CURRENT_MEM_BYTES=$(echo "$VM_INFO" | grep -A 5 "memory:" | tr -s ' ' '\n' | grep -m 1 '^[0-9]\{7,12\}$' || echo "")
    CURRENT_MEM_BYTES=$(echo "$VM_INFO" | grep -A 5 "memory:" | grep "total:" | tr -dc '0-9')
    
    # Get State (Running, Stopped, etc.)
    CURRENT_STATE=$(echo "$VM_INFO" | grep "state:" | head -n1 | awk '{print $3}')
    # Calculate requested bytes (4G -> 4294967296)
    REQ_NUM=$(echo "$MEMORY" | tr -dc '0-9')
    REQUIRED_BYTES=$(( REQ_NUM * 1024 * 1024 * 1024 ))
    echo "   System Reports: $CURRENT_CPUS CPUs and $CURRENT_MEM_BYTES bytes RAM"

    # --- THE COMPARISON WITH MARGIN ---
    SPECS_MATCH=true
    # 1. Check CPU (Usually exact)
    if [ "$CURRENT_CPUS" != "$CPUS" ]; then
        echo "   ❌ CPU Mismatch (Found: $CURRENT_CPUS, Want: $CPUS)"
        SPECS_MATCH=false
    fi
    # 2. Check Memory with a 256MB Margin of Error
    # 256MB = 268,435,456 bytes
    MARGIN=268435456
    if [ -n "$CURRENT_MEM_BYTES" ]; then
        # Calculate the absolute difference
        DIFF=$(( CURRENT_MEM_BYTES - REQUIRED_BYTES ))
        ABS_DIFF=${DIFF#-} # This removes the minus sign if the number is negative
    
        if [ $ABS_DIFF -gt $MARGIN ]; then
            echo "   ❌ Memory Mismatch (Found: $CURRENT_MEM_BYTES, Want: $REQUIRED_BYTES)"
            echo "   (Difference of $(( ABS_DIFF / 1024 / 1024 ))MB exceeds $MARGIN_MB MB margin)"
            SPECS_MATCH=false
        else
            echo "   ✅ Memory matches (within virtualization overhead margin)."
        fi
    else
        echo "   ⚠️  Could not detect Memory. Recreating..."
        SPECS_MATCH=false
    fi

    # --- 1. THE HEARTBEAT CHECK (Vocal Version) ---
    echo "   📡 Verifying OS connectivity..."
    # We capture the output of 'uname -sr' (System name and Kernel Release)
    OS_VERSION=$(multipass exec "$VM_NAME" -- uname -sr 2>/dev/null)
    if [ -n "$OS_VERSION" ]; then
        echo "   ✅ Heartbeat: Connected to $OS_VERSION"
    else
        echo "   ❌ Heartbeat Failed: VM is unresponsive or still booting."
        SPECS_MATCH=false
    fi
    # --- 2. THE DISK SPACE CHECK ---
    echo "   💾 Checking storage..."
    DISK_USAGE=$(multipass exec "$VM_NAME" -- df / --output=pcent | tail -1 | tr -dc '0-9' 2>/dev/null)
    # Check if we actually got a number back (it might be empty if the command timed out)
    if [ -z "$DISK_USAGE" ]; then
        echo "   ❌ Disk Check Failed: Could not retrieve disk stats."
        SPECS_MATCH=false
    elif [ "$DISK_USAGE" -gt 90 ]; then
        echo "   ❌ Disk Warning: $DISK_USAGE% full (Threshold: 90%)"
        SPECS_MATCH=false
    else
        echo "   ✅ Disk Health: $DISK_USAGE% used."
    fi

    # --- 3. THE K8S ENGINE CHECK ---
    # Is the kubelet (the K8s agent) actually running?
    if [ "$SPECS_MATCH" = "true" ]; then # Only check if the VM is actually reachable
        KUBE_STATUS=$(multipass exec "$VM_NAME" -- systemctl is-active kubelet 2>/dev/null || echo "inactive")
        if [ "$KUBE_STATUS" != "active" ]; then
            echo "   ❌ Service Failure: kubelet is $KUBE_STATUS."
            SPECS_MATCH=false
        else
            echo "   ✅ Service Health: kubelet is active."
        fi
    fi

    # --- THE FINAL ACTION ---
    if [ "$SPECS_MATCH" = true ]; then
        echo "   ✅ Specs match. Keeping existing VM."
        if [ "$CURRENT_STATE" != "Running" ]; then
            echo "Starting stopped VM..."
            multipass start "$VM_NAME"
        fi
        SKIP_LAUNCH=true
    else
        echo "⚠️  Specs do not match. Deleting and recreating '$VM_NAME'..."
        multipass delete --purge "$VM_NAME"
        SKIP_LAUNCH=false
    fi
fi

# 3. LAUNCH BLOCK: Only runs if SKIP_LAUNCH is false
if [ "$SKIP_LAUNCH" = false ]; then
    echo "🚀 Action: Launching $VM_NAME using $IMAGE_TO_USE..."
    multipass launch --name "$VM_NAME" \
                     --cpus "$CPUS" \
                     --memory "$MEMORY" \
                     --disk "$DISK" \
                     "$IMAGE_TO_USE"
fi

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

