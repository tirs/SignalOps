# SignalOps Deployment Guide for Hostinger VPS

This guide will help you deploy SignalOps to your Hostinger VPS at https://signalops.syncronhub.com/

## Prerequisites

- Hostinger VPS with SSH access
- Domain pointing to VPS IP (signalops.syncronhub.com)
- MySQL database already set up via phpMyAdmin
- SSH client (PuTTY on Windows or terminal on Mac/Linux)

## Step 1: Connect to Your VPS

Open PowerShell or Command Prompt:

```bash
ssh root@srv1539.hstgr.io
```

Enter your VPS root password when prompted.

## Step 2: Install R and Shiny Server

Run these commands on your VPS:

```bash
# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y software-properties-common dirmngr gnupg apt-transport-https \
    ca-certificates curl libcurl4-openssl-dev libssl-dev libxml2-dev \
    libmariadb-dev libfontconfig1-dev libfreetype6-dev libpng-dev \
    libtiff5-dev libjpeg-dev git nginx certbot python3-certbot-nginx

# Add R repository (for Ubuntu)
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"

# Install R
apt-get update
apt-get install -y r-base r-base-dev

# Install Shiny Server
wget https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.21.1012-amd64.deb
dpkg -i shiny-server-1.5.21.1012-amd64.deb || apt-get install -f -y
rm shiny-server-1.5.21.1012-amd64.deb
```

## Step 3: Install R Packages

```bash
R -e "install.packages(c(
    'shiny', 'bslib', 'DT', 'plotly', 'ggplot2', 'dplyr', 'tidyr',
    'purrr', 'lubridate', 'DBI', 'RMySQL', 'pool', 'config', 'sodium',
    'jsonlite', 'uuid', 'memoise', 'cachem', 'logger', 'htmltools',
    'shinyjs', 'waiter', 'markdown', 'rmarkdown'
), repos='https://cran.rstudio.com/')"
```

## Step 4: Create App Directory

```bash
mkdir -p /srv/shiny-server/signalops
mkdir -p /var/log/signalops
chown -R shiny:shiny /srv/shiny-server/signalops
chown -R shiny:shiny /var/log/signalops
```

## Step 5: Upload App Files

On your Windows machine, use SCP or FileZilla:

### Option A: Using SCP (PowerShell)

```powershell
# Navigate to SignalOps folder
cd C:\Users\simba\Desktop\SignalOps

# Upload app folder
scp -r app/* root@srv1539.hstgr.io:/srv/shiny-server/signalops/
```

### Option B: Using FileZilla

1. Connect to srv1539.hstgr.io with SFTP
2. Navigate to /srv/shiny-server/signalops/
3. Upload all files from C:\Users\simba\Desktop\SignalOps\app\

## Step 6: Configure Database Connection

Create the config file on the server:

```bash
nano /srv/shiny-server/signalops/config.yml
```

Update the database section with your actual credentials:

```yaml
default:
  database:
    db_type: "mysql"
    host: "localhost"
    port: 3306
    dbname: "your_database_name"
    user: "your_database_user"
    password: "your_database_password"
    pool_size: 5
  
  app:
    name: "SignalOps"
    version: "1.0.0"
    environment: "production"
    debug: false
    log_level: "info"
    session_timeout: 28800
```

Save and exit (Ctrl+X, Y, Enter).

Set permissions:

```bash
chown -R shiny:shiny /srv/shiny-server/signalops
chmod 600 /srv/shiny-server/signalops/config.yml
```

## Step 7: Configure Nginx Reverse Proxy

```bash
# Create nginx config
nano /etc/nginx/sites-available/signalops
```

Paste this configuration:

```nginx
server {
    listen 80;
    server_name signalops.syncronhub.com;
    
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
        client_max_body_size 50M;
    }
}
```

Enable the site:

```bash
ln -s /etc/nginx/sites-available/signalops /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

## Step 8: Enable SSL (HTTPS)

```bash
certbot --nginx -d signalops.syncronhub.com
```

Follow the prompts:
- Enter your email
- Agree to terms
- Choose to redirect HTTP to HTTPS

## Step 9: Start/Restart Services

```bash
systemctl restart shiny-server
systemctl restart nginx
systemctl enable shiny-server
systemctl enable nginx
```

## Step 10: Verify Deployment

1. Check Shiny Server status:
   ```bash
   systemctl status shiny-server
   ```

2. Check logs for errors:
   ```bash
   tail -f /var/log/shiny-server.log
   tail -f /var/log/signalops/*.log
   ```

3. Visit https://signalops.syncronhub.com in your browser

## Default Login Credentials

| Email | Password | Role |
|-------|----------|------|
| admin@signalops.io | admin123 | Admin |
| analyst@signalops.io | admin123 | Analyst |
| viewer@signalops.io | admin123 | Viewer |

## Troubleshooting

### App not loading
```bash
# Check Shiny Server logs
tail -100 /var/log/shiny-server.log

# Check app-specific logs
ls -la /var/log/shiny-server/
cat /var/log/shiny-server/signalops-*.log
```

### Database connection issues
```bash
# Test MySQL connection from server
mysql -h localhost -u your_user -p your_database
```

### Permission issues
```bash
chown -R shiny:shiny /srv/shiny-server/signalops
chmod -R 755 /srv/shiny-server/signalops
```

### Nginx issues
```bash
nginx -t
systemctl status nginx
tail -f /var/log/nginx/error.log
```

## Updating the App

To deploy updates:

```powershell
# From Windows PowerShell
cd C:\Users\simba\Desktop\SignalOps
scp -r app/* root@srv1539.hstgr.io:/srv/shiny-server/signalops/
ssh root@srv1539.hstgr.io "chown -R shiny:shiny /srv/shiny-server/signalops && systemctl restart shiny-server"
```

## Firewall Configuration

Ensure these ports are open:
- 22 (SSH)
- 80 (HTTP)
- 443 (HTTPS)
- 3306 (MySQL - if external access needed)

```bash
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable
```
