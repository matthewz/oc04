#!/bin/bash

set -e

# Arguments
VM_NAME="${1}"

echo "=================================================="
echo "Installing Longhorn dependencies on ${VM_NAME}"
echo "=================================================="

multipass exec ${VM_NAME} -- bash -c "
set -e
echo '🔧 Configuring longhorn dependencies...'
set -x
sudo apt-get update
sudo apt-get install -y open-iscsi nfs-common
sudo systemctl enable iscsid
sudo systemctl restart iscsid
set +x
sleep 5
echo 'Verify iscsid is running...'
set -x
sudo systemctl status iscsid
set +x
echo 'Exit back to host'
"
