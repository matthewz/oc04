#!/bin/bash
set -x
K8S_V="1.28.0-1.1" 
GOLDEN_NAME="k8s-golden-$(date +%Y%m%d)"
# 1. Launch
echo "--- Launching temporary VM ---"
multipass launch --name k8s-temp --cpus 2 --memory 4G --disk 20G
# 2. Transfer
echo "--- Transferring bake script ---"
multipass transfer scripts/bake-k8s.sh k8s-temp:/tmp/
# 3. Bake
echo "--- Baking K8s $K8S_V ---"
multipass exec k8s-temp -- bash /tmp/bake-k8s.sh "$K8S_V"
# ... after the bake ...
# 4. Locate and Copy
echo "--- Locating Disk Image ---"
# We need sudo to peek into the Multipass vault
DISK_FILE=$(sudo find "/var/root/Library/Application Support/multipassd/qemu/vault/instances/k8s-temp" -name "*.img" -o -name "*.qcow2" 2>/dev/null | head -n 1)
echo "--- Stopping VM ---"
multipass stop k8s-temp
if [ -n "$DISK_FILE" ]; then
    echo "--- Found disk at: $DISK_FILE ---"
    echo "--- Copying image (this may take a moment)... ---"
    sudo cp -v "$DISK_FILE" "$GOLDEN_NAME.img"
    # Change ownership of the copy so YOU own it, not root
    sudo chown $(whoami) "$GOLDEN_NAME.img"
    echo "--- SUCCESS: Golden Image saved to $GOLDEN_NAME.img ---"
else
    echo "--- ERROR: Could not find the disk image in the vault! ---"
    exit 1
fi
# 5. Cleanup
echo "--- Cleaning up temporary VM ---"
multipass delete k8s-temp
multipass purge
echo "--- Finished. Your Golden Image is ready. ---"
