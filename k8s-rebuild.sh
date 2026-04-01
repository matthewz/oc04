#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Constants
MULTIPASS_DIR="/private/var/root/Library/Application Support/multipassd/"
JOIN_FILE="./out/join-command.sh"
MAX_RETRIES=30
SAFE_MODE=false  # set to true with --safe flag

# Parse flags
for arg in "$@"; do
    case $arg in
        --safe)
            SAFE_MODE=true
            ;;
    esac
done

# Check the external SSD
check_storage_volume() {
    echo "🔍 Checking external storage volume..."
    
    if [ ! -d "/Volumes/PRO-G40/multipassd" ]; then
        echo -e "${RED}❌ ERROR: /Volumes/PRO-G40 is not mounted.${NC}"
        echo "    Multipass VM data lives there — aborting to prevent data loss."
        exit 1
    fi
    
    # In safe mode, warn if VMs already exist before destroying them
    if [ "$SAFE_MODE" = true ]; then
        VM_COUNT=$(multipass list --format csv | grep -c "k8s-" || true)
        if [ "$VM_COUNT" -gt 0 ]; then
            echo -e "${RED}⚠️  SAFE MODE: Found $VM_COUNT existing k8s VM(s).${NC}"
            echo "    Run without --safe to delete and rebuild them."
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✅ Storage volume healthy${NC}"
}

# Function to exclude directory from Time Machine
exclude_from_time_machine() {
    echo "Excluding multipass directory from time machine..."
    set -x
    sudo tmutil addexclusion "$MULTIPASS_DIR"
    sudo tmutil isexcluded "$MULTIPASS_DIR"
    set +x
}

# Function to pause and re-enable Time Machine
pause_time_machine() {
    echo "⏸️  Pausing Time Machine for duration of provisioning..."
    set -x
    sudo tmutil disable
    sudo tmutil status
    set +x

    # Ensure Time Machine is ALWAYS re-enabled when script exits
    #trap 'echo "▶️  Re-enabling Time Machine..."; sudo tmutil enable' EXIT
}

# Function to check if Multipass is installed
check_multipass_installed() {
    echo -e "${BLUE}🚀 Starting Kubernetes Rebuild Process...${NC}"
    if ! command -v multipass &> /dev/null; then
        echo -e "${RED}❌ Error: Multipass is not installed.${NC}"
        exit 1
    fi
}

# Function to destroy existing infrastructure
destroy_infrastructure() {
    export REPLY="Y"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}🧨 Phase 1: Total Destruction...${NC}"
        terraform destroy -auto-approve
    fi
}

# Function to clean workspace
clean_workspace() {
    echo -e "${GREEN}🧹 Phase 2: Cleaning Workspace...${NC}"
    mkdir -p ./out
    rm -rf ./out/*
    rm -f ./output.tfplan ./tfplan.txt
}

# Function to initialize and format Terraform
initialize_terraform() {
    echo -e "${GREEN}⚙️ Phase 3: Initializing & Formatting...${NC}"
    terraform fmt
    terraform init
}

# Function to plan infrastructure
plan_infrastructure() {
    echo -e "${GREEN}📝 Phase 4: Planning Infrastructure...${NC}"
    terraform plan -out=./output.tfplan -input=false
}

# Function to apply infrastructure
apply_infrastructure() {
    echo -e "${GREEN}🚀 Phase 5: Applying Infrastructure...${NC}"
    # Terraform will now create the VMs and run the Master-Init script
    terraform apply "./output.tfplan"
}

# Function to orchestrate worker joins
orchestrate_worker_joins() {
    echo -e "${BLUE}🔗 Phase 6: Orchestrating Worker Joins...${NC}"
    
    # Wait for the Master to finish writing the join file to your Mac
    COUNT=0
    echo "⏳ Waiting for Master to generate join command..."
    while [ ! -f "$JOIN_FILE" ]; do
        if [ $COUNT -ge $MAX_RETRIES ]; then
            echo -e "${RED}❌ Error: Join command file never appeared in $JOIN_FILE${NC}"
            exit 1
        fi
        echo "   ...still waiting for Master (Attempt $((COUNT+1))/$MAX_RETRIES)"
        sleep 10
        COUNT=$((COUNT+1))
    done

    # Read the join command into a variable on your Mac
    JOIN_CMD=$(cat "$JOIN_FILE" | tr -d '\r\n' | sed 's/#!/ /g' | sed 's/\/bin\/bash/ /g')
    echo -e "${GREEN}✅ Join command captured!${NC}"

    # Execute the join on all workers
    WORKERS=$(multipass list --format csv | awk -F, '$1 ~ /worker/ {print $1}')
    for WORKER in $WORKERS; do
        echo -e "${BLUE}🔄 Resetting $WORKER before join...${NC}"
        multipass exec "$WORKER" -- sudo kubeadm reset -f
        multipass exec "$WORKER" -- sudo rm -rf /etc/kubernetes /var/lib/kubelet
        echo -e "${BLUE}🚀 Joining $WORKER to the cluster...${NC}"
        multipass exec "$WORKER" -- sudo bash -c "$JOIN_CMD"
    done
    echo -e "${GREEN}✅ Cluster rebuild complete!${NC}"
}

# Function to display final status
display_final_status() {
    echo -e "${BLUE}Final Status:${NC}"
    multipass list
    echo -e "${BLUE}Checking Node Status from Master:${NC}"
    multipass exec k8s-master -- kubectl get nodes -o wide
}

# Main function
main() {
    check_storage_volume
    exclude_from_time_machine
    pause_time_machine
    echo "=================================================="
    echo "      Starting Kubernetes Cluster Rebuild"
    echo "=================================================="
    check_multipass_installed
    clean_workspace          # ← moved up
    initialize_terraform     # ← moved up (init before destroy)
    destroy_infrastructure   # ← now has a valid lock file
    plan_infrastructure
    apply_infrastructure
    orchestrate_worker_joins
    display_final_status
}

# Run the main function
main
