#!/bin/bash
set -euo pipefail
# ============================================================
echo "Excluding multipass directory from time machine..."
# ============================================================
set -x
sudo tmutil addexclusion /private/var/root/Library/Application\ Support/multipassd/ 
sudo tmutil isexcluded /private/var/root/Library/Application\ Support/multipassd/
set +x
echo "⏸️  Pausing Time Machine for duration of provisioning..."
set -x
sudo tmutil disable
sudo tmutil status
set +x
# Ensure Time Machine is ALWAYS re-enabled when script exits
trap 'echo "▶️  Re-enabling Time Machine..."; sudo tmutil enable' EXIT
# ============================================================
echo "=================================================="
echo "      Starting Kubernetes Cluster Rebuild"
echo "=================================================="
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
echo -e "${BLUE}🚀 Starting Kubernetes Rebuild Process...${NC}"
# 1. Validation Check
if ! command -v multipass &> /dev/null; then
    echo -e "${RED}❌ Error: Multipass is not installed.${NC}"
    exit 1
fi
# 2. Destruction
export REPLY="Y"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}🧨 Phase 1: Total Destruction...${NC}"
    terraform destroy -auto-approve
fi
echo -e "${GREEN}🧹 Phase 2: Cleaning Workspace...${NC}"
mkdir -p ./out
rm -rf ./out/*
rm -f ./output.tfplan ./tfplan.txt
echo -e "${GREEN}⚙️ Phase 3: Initializing & Formatting...${NC}"
terraform fmt
terraform init
echo -e "${GREEN}📝 Phase 4: Planning Infrastructure...${NC}"
terraform plan -out=./output.tfplan -input=false
echo -e "${GREEN}🚀 Phase 5: Applying Infrastructure...${NC}"
# Terraform will now create the VMs and run the Master-Init script
terraform apply "./output.tfplan"
# ============================================================
# 🚀 NEW PHASE 6: THE JOINER (Manual Worker Orchestration)
# ============================================================
echo -e "${BLUE}🔗 Phase 6: Orchestrating Worker Joins...${NC}"
# 1. Wait for the Master to finish writing the join file to your Mac
JOIN_FILE="./out/join-command.sh"
MAX_RETRIES=30
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
# 2. Read the join command into a variable on your Mac
# We use 'tr' to strip any hidden newline characters that might break the command
JOIN_CMD=$(cat "$JOIN_FILE" | tr -d '\r\n' | sed 's/#!/ /g' | sed 's/\/bin\/bash/ /g')
echo -e "${GREEN}✅ Join command captured!${NC}"
# 3. Execute the join on all workers
# We iterate through all workers found in multipass that aren't the master
WORKERS=$(multipass list --format csv | awk -F, '$1 ~ /worker/ {print $1}')
for WORKER in $WORKERS; do
    echo -e "${BLUE}🚀 Joining $WORKER to the cluster...${NC}"
    # Run the join command with sudo inside the worker VM
    multipass exec "$WORKER" -- sudo bash -c "$JOIN_CMD"
done
echo -e "${GREEN}✅ Cluster rebuild complete!${NC}"
echo -e "${BLUE}Final Status:${NC}"
multipass list
echo -e "${BLUE}Checking Node Status from Master:${NC}"
multipass exec k8s-master -- kubectl get nodes -o wide1G
