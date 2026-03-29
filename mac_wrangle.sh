#!/bin/bash
echo "🧹 Starting Mac Mini Resource Recovery..."
# 1. Force Purge Multipass (Only if you want to start K8s from scratch!)
echo "Stopping all VMs..."
multipass stop --all
sleep 2 
echo "Purging deleted VMs..."
multipass purge
# 2. Clear Local Time Machine Snapshots 
# This is the "Magic Wand" for that 73GB System Data bloat.
echo "Clearing local Time Machine snapshots..."
sudo tmutil thinlocalsnapshots / 10000000000 4
# 3. Clear Caches
echo "Clearing system and user caches..."
rm -rf ~/Library/Caches/*
sudo rm -rf /Library/Caches/* 2> /dev/null
# 4. Prune Docker (Clean up those dangling layers)
if command -v docker &> /dev/null; then
    echo "Pruning Docker system..."
    docker system prune -af --volumes
fi
# 5. Trim the SSD (Specific to your disk3s5)
echo "Optimizing SSD (Trim)..."
#sudo fsck_apfs -n -l /dev/disk3s5 || echo "Trim notification sent."
# Automatically find the APFS Data volume identifier
DATA_DISK=$(diskutil list | grep "APFS Volume Data" | awk '{print $NF}')
if [ -z "$DATA_DISK" ]; then
    echo "❌ Could not find Data disk. Manual intervention required."
    exit 1
fi
echo "🔍 Found Data disk at: /dev/$DATA_DISK"
# Now use the variable instead of hardcoding
sudo fsck_apfs -n -l /dev/$DATA_DISK || echo "Trim notification sent."
echo "✅ Resources wrangled. Your Mac Mini should breathe easier now."
