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
set +x
# Ensure Time Machine is ALWAYS re-enabled when script exits,
# even if it exits due to an error (that's what trap does)
trap 'echo "▶️  Re-enabling Time Machine..."; sudo tmutil enable' EXIT
###
# ============================================================
echo "=================================================="
echo "      Starting Kubernetes Cluster Rebuild"
echo "=================================================="
# Colors for better readability
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
# 2. Optional Destruction
# SRE Tip: Instead of always destroying, we ask. 
# Remove the 'if' block if you truly want it automated every time.
###
#read -p "Do you want to wipe the existing cluster first? (y/n) " -n 1 -r
#echo
###
export REPLY="Y"
###
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}🧨 Phase 1: Total Destruction...${NC}"
    terraform destroy -auto-approve
fi
echo -e "${GREEN}🧹 Phase 2: Cleaning Workspace...${NC}"
rm -rf ./out/*.txt
rm -f ./output.tfplan ./tfplan.txt
echo -e "${GREEN}⚙️ Phase 3: Initializing & Formatting...${NC}"
terraform fmt
terraform init
echo -e "${GREEN}📝 Phase 4: Planning Infrastructure...${NC}"
# Use -input=false for automation
terraform plan -out=./output.tfplan -input=false
# 5. Review Step
echo -e "${BLUE}Ready to apply the plan above?${NC}"
#read -p "Press enter to continue or Ctrl+C to abort..."
echo -e "${GREEN}🚀 Phase 5: Applying (Serial Build)...${NC}"
# We apply the plan file directly. 
# Note: --auto-approve is not needed when applying a plan file.
terraform apply "./output.tfplan"
echo -e "${GREEN}✅ Cluster rebuild complete!${NC}"
echo -e "${BLUE}Final Status:${NC}"
multipass list
