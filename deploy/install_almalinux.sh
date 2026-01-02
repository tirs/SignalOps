#!/bin/bash
# ============================================================
# SignalOps - Server Installation Script for AlmaLinux 10
# Run as root on your Hostinger VPS
# ============================================================

set -e

echo "=== SignalOps Server Setup for AlmaLinux 10 ==="

# Update system
dnf update -y

# Enable EPEL and CRB repositories
dnf install -y epel-release
dnf config-manager --set-enabled crb

# Install dependencies
dnf install -y \
    curl \
    wget \
    git \
    nginx \
    certbot \
    python3-certbot-nginx \
    openssl-devel \
    libcurl-devel \
    libxml2-devel \
    mariadb-devel \
    fontconfig-devel \
    freetype-devel \
    libpng-devel \
    libtiff-devel \
    libjpeg-turbo-devel \
    cairo-devel \
    pango-devel \
    harfbuzz-devel \
    fribidi-devel \
    make \
    gcc \
    gcc-c++ \
    R-core \
    R-core-devel

# If R is not available from default repos, add EPEL or build from source
if ! command -v R &> /dev/null; then
    echo "Installing R from source..."
    dnf groupinstall -y "Development Tools"
    dnf install -y readline-devel xz-devel bzip2-devel pcre2-devel
    
    cd /tmp
    wget https://cran.r-project.org/src/base/R-4/R-4.3.2.tar.gz
    tar -xzf R-4.3.2.tar.gz
    cd R-4.3.2
    ./configure --enable-R-shlib --with-blas --with-lapack
    make -j$(nproc)
    make install
    cd /
    rm -rf /tmp/R-4.3.2*
fi

# Install Shiny Server
echo "Installing Shiny Server..."
cd /tmp
wget https://download3.rstudio.org/centos7/x86_64/shiny-server-1.5.21.1012-x86_64.rpm
dnf install -y ./shiny-server-1.5.21.1012-x86_64.rpm || yum localinstall -y ./shiny-server-1.5.21.1012-x86_64.rpm
rm -f shiny-server-1.5.21.1012-x86_64.rpm

# Install R packages
echo "Installing R packages..."
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
    'rmarkdown'
), repos='https://cran.rstudio.com/', Ncpus=4)"

# Create app directory
mkdir -p /srv/shiny-server/signalops
mkdir -p /var/log/signalops

# Set permissions
chown -R shiny:shiny /srv/shiny-server/signalops
chown -R shiny:shiny /var/log/signalops

# Configure firewall
echo "Configuring firewall..."
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=3838/tcp
firewall-cmd --reload

# Enable services
systemctl enable nginx
systemctl enable shiny-server
systemctl start nginx
systemctl start shiny-server

# SELinux configuration
echo "Configuring SELinux..."
setsebool -P httpd_can_network_connect 1

echo ""
echo "=== Server installation complete ==="
echo ""
echo "Next steps:"
echo "1. Upload app files to /srv/shiny-server/signalops/"
echo "2. Configure database credentials in config.yml"
echo "3. Set up Nginx reverse proxy"
echo "4. Enable SSL with certbot"
