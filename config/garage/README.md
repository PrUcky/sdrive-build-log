# Garage S3 Storage Engine Configuration

This directory contains the production service unit and configuration templates for the **Garage** S3-compatible object storage daemon running on the `sdrive` single-board computer appliance.

---

## 1. Quick Setup & Initialization

### Step 1: Install Garage Binary (ARM64)
```bash
# Download latest static ARM64 binary
curl -fsSL -o /usr/local/bin/garage \
  https://garagehq.deuxfleurs.fr/_releases/v0.9.4/arm64-unknown-linux-musl/garage
chmod +x /usr/local/bin/garage

# Create dedicated unprivileged user and directories
useradd -r -s /bin/false sdrive-garage
mkdir -p /var/lib/garage/meta /var/lib/garage/data /etc/garage
chown -R sdrive-garage:sdrive-garage /var/lib/garage
```

### Step 2: Deploy Configuration
```bash
# Generate unique secrets
RPC_SECRET=$(openssl rand -hex 32)
ADMIN_TOKEN=$(openssl rand -hex 32)

# Copy and populate template
cp config/garage/garage.toml.example /etc/garage.toml
sed -i "s/REPLACE_WITH_GENERATED_RPC_SECRET_32_BYTES_HEX/$RPC_SECRET/" /etc/garage.toml
sed -i "s/REPLACE_WITH_SECURE_ADMIN_TOKEN_HEX/$ADMIN_TOKEN/" /etc/garage.toml
chmod 600 /etc/garage.toml
```

### Step 3: Enable & Start Systemd Service
```bash
cp config/garage/garage.service /etc/systemd/system/garage.service
systemctl daemon-reload
systemctl enable --now garage.service
systemctl status garage.service
```

### Step 4: Initialize Cluster Layout & Primary Bucket
```bash
# Get node ID
NODE_ID=$(garage status | grep "Node ID" | awk '{print $3}')

# Assign node to single-node layout (Zone: home, Capacity: 500G, Tags: sdrive)
garage layout assign -z home -c 500G -t sdrive $NODE_ID
garage layout apply --version 1

# Create primary sdrive bucket and generate S3 access credentials
garage bucket create sdrive-data
garage key create sdrive-museum-key
garage bucket allow --read --write --key sdrive-museum-key sdrive-data
```
