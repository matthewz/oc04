#!/bin/bash
# install-vault.sh
# Called by Terraform 
# Usage: install-vault.sh <vm-name> <vm-ip>
set -euo pipefail
VM_NAME=$1
VM_IP=$2
echo "==> Installing Vault on ${VM_NAME} (${VM_IP})"
multipass exec "${VM_NAME}" -- bash -c "
  set -euo pipefail
  # Install Vault
  wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp.gpg > /dev/null
  echo 'deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com jammy main' | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -qq && sudo apt-get install -y vault
  # Write config
  sudo tee /etc/vault.d/vault.hcl > /dev/null <<EOF
ui            = true
disable_mlock = true
storage \"file\" {
  path = \"/opt/vault/data\"
}
listener \"tcp\" {
  address     = \"0.0.0.0:8200\"
  tls_disable = true
}
api_addr = \"http://${VM_IP}:8200\"
EOF
  # Create data dir and fix permissions
  sudo mkdir -p /opt/vault/data
  sudo chown -R vault:vault /opt/vault/data
  # Enable and start
  sudo systemctl enable vault
  sudo systemctl start vault
  echo 'Vault installed and running'
"
echo "==> Vault ready at http://${VM_IP}:8200"
