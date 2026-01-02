#!/bin/bash
# ============================================================
# SignalOps - Deployment Script
# Run this from your local machine to deploy to VPS
# ============================================================

set -e

# Configuration - UPDATE THESE VALUES
VPS_HOST="srv1539.hstgr.io"
VPS_USER="root"
APP_PATH="/srv/shiny-server/signalops"

echo "=== Deploying SignalOps to $VPS_HOST ==="

# Create deployment package
echo "Creating deployment package..."
cd "$(dirname "$0")/.."

# Create temp directory for deployment
rm -rf /tmp/signalops_deploy
mkdir -p /tmp/signalops_deploy

# Copy app files
cp -r app/* /tmp/signalops_deploy/
cp app/config.yml /tmp/signalops_deploy/

# Create tarball
cd /tmp
tar -czf signalops.tar.gz signalops_deploy

# Upload to server
echo "Uploading to server..."
scp signalops.tar.gz ${VPS_USER}@${VPS_HOST}:/tmp/

# Deploy on server
echo "Deploying on server..."
ssh ${VPS_USER}@${VPS_HOST} << 'ENDSSH'
    # Extract files
    cd /tmp
    tar -xzf signalops.tar.gz
    
    # Stop Shiny Server
    systemctl stop shiny-server || true
    
    # Backup current deployment
    if [ -d "/srv/shiny-server/signalops" ]; then
        mv /srv/shiny-server/signalops /srv/shiny-server/signalops_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    # Deploy new version
    mv /tmp/signalops_deploy /srv/shiny-server/signalops
    
    # Set permissions
    chown -R shiny:shiny /srv/shiny-server/signalops
    chmod -R 755 /srv/shiny-server/signalops
    
    # Start Shiny Server
    systemctl start shiny-server
    
    # Cleanup
    rm -f /tmp/signalops.tar.gz
    
    echo "Deployment complete!"
ENDSSH

# Cleanup local temp files
rm -rf /tmp/signalops_deploy
rm -f /tmp/signalops.tar.gz

echo ""
echo "=== Deployment Complete ==="
echo "Visit: https://signalops.syncronhub.com"
