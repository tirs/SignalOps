#!/bin/bash
# ============================================================
# SignalOps - Server Installation Script for Ubuntu/Debian VPS
# Run as root on your Hostinger VPS
# ============================================================

set -e

echo "=== SignalOps Server Setup ==="
echo "Installing R and Shiny Server on Ubuntu/Debian..."

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y \
    software-properties-common \
    dirmngr \
    gnupg \
    apt-transport-https \
    ca-certificates \
    curl \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libmariadb-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    git \
    nginx \
    certbot \
    python3-certbot-nginx

# Add R repository
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"

# Install R
apt-get update
apt-get install -y r-base r-base-dev

# Install Shiny Server
wget https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.21.1012-amd64.deb
dpkg -i shiny-server-1.5.21.1012-amd64.deb || apt-get install -f -y
rm shiny-server-1.5.21.1012-amd64.deb

# Install R packages as root (system-wide)
R -e "install.packages(c(
    'shiny',
    'bslib',
    'DT',
    'plotly',
    'ggplot2',
    'dplyr',
    'tidyr',
    'purrr',
    'lubridate',
    'DBI',
    'RMySQL',
    'pool',
    'config',
    'sodium',
    'jsonlite',
    'uuid',
    'memoise',
    'cachem',
    'logger',
    'htmltools',
    'shinyjs',
    'waiter',
    'markdown',
    'rmarkdown',
    'tinytex'
), repos='https://cran.rstudio.com/')"

# Create app directory
mkdir -p /srv/shiny-server/signalops
mkdir -p /var/log/signalops

# Set permissions
chown -R shiny:shiny /srv/shiny-server/signalops
chown -R shiny:shiny /var/log/signalops

echo ""
echo "=== Server installation complete ==="
echo "Next steps:"
echo "1. Upload your app files to /srv/shiny-server/signalops/"
echo "2. Configure environment variables"
echo "3. Set up Nginx reverse proxy"
echo "4. Enable SSL with Let's Encrypt"
