# SignalOps Deployment Guide for AlmaLinux 10

Deploy SignalOps to your Hostinger VPS at https://signalops.syncronhub.com/

## VPS Details
- **OS**: AlmaLinux 10
- **Hostname**: srv815965.hstgr.cloud  
- **IP**: 157.173.210.171
- **SSH User**: root

## Prerequisites
- SSH access to VPS
- Domain DNS pointing to 157.173.210.171
- MySQL database set up via phpMyAdmin

---

## Step 1: Connect to VPS

Open PowerShell on Windows:

```powershell
ssh root@157.173.210.171
```

Enter your root password when prompted.

---

## Step 2: Update System and Install Dependencies

```bash
# Update system
dnf update -y

# Enable EPEL repository
dnf install -y epel-release
dnf config-manager --set-enabled crb

# Install build dependencies
dnf install -y curl wget git nginx certbot python3-certbot-nginx \
    openssl-devel libcurl-devel libxml2-devel mariadb-devel \
    fontconfig-devel freetype-devel libpng-devel libtiff-devel \
    libjpeg-turbo-devel cairo-devel pango-devel make gcc gcc-c++
```

---

## Step 3: Install R

```bash
# Try to install R from repos first
dnf install -y R-core R-core-devel

# Verify R is installed
R --version
```

If R is not available, install from source:

```bash
dnf groupinstall -y "Development Tools"
dnf install -y readline-devel xz-devel bzip2-devel pcre2-devel

cd /tmp
wget https://cran.r-project.org/src/base/R-4/R-4.3.2.tar.gz
tar -xzf R-4.3.2.tar.gz
cd R-4.3.2
./configure --enable-R-shlib --with-blas --with-lapack
make -j$(nproc)
make install
```

---

## Step 4: Install Shiny Server

```bash
cd /tmp
wget https://download3.rstudio.org/centos7/x86_64/shiny-server-1.5.21.1012-x86_64.rpm
dnf install -y ./shiny-server-1.5.21.1012-x86_64.rpm
rm -f shiny-server-1.5.21.1012-x86_64.rpm
```

---

## Step 5: Install R Packages

```bash
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
    'markdown'
), repos='https://cran.rstudio.com/', Ncpus=4)"
```

This may take 10-15 minutes. Wait for it to complete.

---

## Step 6: Create App Directory

```bash
mkdir -p /srv/shiny-server/signalops
mkdir -p /var/log/signalops
chown -R shiny:shiny /srv/shiny-server/signalops
chown -R shiny:shiny /var/log/signalops
```

---

## Step 7: Upload App Files

**On your Windows machine**, open a new PowerShell window:

```powershell
cd C:\Users\simba\Desktop\SignalOps

# Upload all app files
scp -r app/* root@157.173.210.171:/srv/shiny-server/signalops/
```

---

## Step 8: Configure Database Connection

Back on the VPS, edit the config file:

```bash
nano /srv/shiny-server/signalops/config.yml
```

Update the database section with your actual phpMyAdmin credentials:

```yaml
default:
  database:
    db_type: "mysql"
    host: "localhost"
    port: 3306
    dbname: "YOUR_DATABASE_NAME"
    user: "YOUR_DATABASE_USER"
    password: "YOUR_DATABASE_PASSWORD"
    pool_size: 5
  
  app:
    name: "SignalOps"
    version: "1.0.0"
    environment: "production"
    debug: false
    log_level: "info"
    session_timeout: 28800
```

Save: Press `Ctrl+X`, then `Y`, then `Enter`

Set permissions:

```bash
chown -R shiny:shiny /srv/shiny-server/signalops
chmod 600 /srv/shiny-server/signalops/config.yml
```

---

## Step 9: Configure Nginx

```bash
nano /etc/nginx/conf.d/signalops.conf
```

Paste this:

```nginx
server {
    listen 80;
    server_name signalops.syncronhub.com;
    
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://127.0.0.1:3838/signalops/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        proxy_buffering off;
    }
}
```

Save and exit (`Ctrl+X`, `Y`, `Enter`).

Test and reload Nginx:

```bash
nginx -t
systemctl restart nginx
```

---

## Step 10: Configure Firewall

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

---

## Step 11: Configure SELinux

```bash
setsebool -P httpd_can_network_connect 1
```

---

## Step 12: Start Services

```bash
systemctl enable shiny-server
systemctl enable nginx
systemctl restart shiny-server
systemctl restart nginx
```

---

## Step 13: Enable SSL (HTTPS)

Make sure your DNS is pointing signalops.syncronhub.com to 157.173.210.171, then:

```bash
certbot --nginx -d signalops.syncronhub.com
```

Follow the prompts:
1. Enter your email
2. Accept terms
3. Choose to redirect HTTP to HTTPS (option 2)

---

## Step 14: Verify Deployment

Check service status:

```bash
systemctl status shiny-server
systemctl status nginx
```

Check for errors:

```bash
tail -50 /var/log/shiny-server.log
```

Visit: https://signalops.syncronhub.com

---

## Login Credentials

| Email | Password | Role |
|-------|----------|------|
| admin@signalops.io | admin123 | Admin |
| analyst@signalops.io | admin123 | Analyst |
| viewer@signalops.io | admin123 | Viewer |

---

## Troubleshooting

### App not loading

```bash
# Check Shiny logs
tail -100 /var/log/shiny-server.log
ls -la /var/log/shiny-server/
```

### SELinux blocking connections

```bash
# Check SELinux denials
ausearch -m AVC -ts recent
# Temporarily disable for testing (not recommended for production)
setenforce 0
```

### Database connection failed

```bash
# Test MySQL connection
mysql -h localhost -u your_user -p your_database
```

### Permission denied

```bash
chown -R shiny:shiny /srv/shiny-server/signalops
chmod -R 755 /srv/shiny-server/signalops
restorecon -Rv /srv/shiny-server/signalops
```

---

## Updating the App

From Windows PowerShell:

```powershell
cd C:\Users\simba\Desktop\SignalOps
scp -r app/* root@157.173.210.171:/srv/shiny-server/signalops/
ssh root@157.173.210.171 "chown -R shiny:shiny /srv/shiny-server/signalops && systemctl restart shiny-server"
```

---

## Quick Command Reference

```bash
# Check status
systemctl status shiny-server
systemctl status nginx

# View logs
tail -f /var/log/shiny-server.log
tail -f /var/log/nginx/error.log

# Restart services
systemctl restart shiny-server
systemctl restart nginx
```
