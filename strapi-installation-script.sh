#!/bin/bash

# Strapi Installation Script for Ubuntu 22.04
# This script will install Strapi and all necessary dependencies
# with minimal password prompts

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Strapi Installation Script for Ubuntu 22.04 ===${NC}"
echo -e "${YELLOW}This script will install Strapi and all required dependencies.${NC}"
echo -e "${YELLOW}You will be asked for your password once at the beginning.${NC}"
echo ""

# Request sudo privileges upfront
sudo -v

# Keep sudo privilege throughout the script execution
(while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null) &

# Update package lists
echo -e "\n${GREEN}Updating package lists...${NC}"
sudo apt-get update

# Install essential tools
echo -e "\n${GREEN}Installing essential tools...${NC}"
sudo apt-get install -y curl wget git build-essential

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "\n${GREEN}Node.js not found. Installing Node.js 20.x...${NC}"
    # Install Node.js 20.x (LTS)
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    NODE_VERSION=$(node -v)
    echo -e "\n${GREEN}Node.js ${NODE_VERSION} is already installed.${NC}"
    
    # Check if Node.js version is compatible with Strapi
    NODE_MAJOR_VERSION=$(node -v | cut -d. -f1 | tr -d 'v')
    if [ $NODE_MAJOR_VERSION -lt 14 ] || [ $NODE_MAJOR_VERSION -gt 20 ]; then
        echo -e "\n${YELLOW}Warning: Strapi works best with Node.js versions 14 through 20.${NC}"
        echo -e "${YELLOW}Current version: ${NODE_VERSION}${NC}"
        echo -e "${YELLOW}Installing Node.js 20.x...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo -e "\n${GREEN}npm not found. Installing npm...${NC}"
    sudo apt-get install -y npm
else
    NPM_VERSION=$(npm -v)
    echo -e "\n${GREEN}npm ${NPM_VERSION} is already installed.${NC}"
fi

# Update npm to latest version
echo -e "\n${GREEN}Updating npm to the latest version...${NC}"
sudo npm install -g npm@latest

# Install Yarn (optional but recommended for Strapi)
if ! command -v yarn &> /dev/null; then
    echo -e "\n${GREEN}Yarn not found. Installing Yarn...${NC}"
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    sudo apt-get update && sudo apt-get install -y yarn
else
    YARN_VERSION=$(yarn -v)
    echo -e "\n${GREEN}Yarn ${YARN_VERSION} is already installed.${NC}"
fi

# Install PostgreSQL (recommended database for production)
echo -e "\n${GREEN}Installing PostgreSQL...${NC}"
sudo apt-get install -y postgresql postgresql-contrib

# Start and enable PostgreSQL
echo -e "\n${GREEN}Starting PostgreSQL service...${NC}"
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Setup PostgreSQL for Strapi
echo -e "\n${GREEN}Setting up PostgreSQL database for Strapi...${NC}"
sudo -u postgres psql -c "CREATE DATABASE strapi;"
sudo -u postgres psql -c "CREATE USER strapi WITH ENCRYPTED PASSWORD 'strapipassword';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE strapi TO strapi;"

# Create Strapi project
echo -e "\n${GREEN}Creating Strapi project...${NC}"
read -p "Enter the directory path for your Strapi project (default: /var/www/strapi): " STRAPI_PATH
STRAPI_PATH=${STRAPI_PATH:-/var/www/strapi}

# Create directory if it doesn't exist
sudo mkdir -p $STRAPI_PATH
sudo chown -R $USER:$USER $STRAPI_PATH

# Navigate to the directory
cd $STRAPI_PATH

# Create Strapi project with PostgreSQL
echo -e "\n${GREEN}Creating new Strapi project with PostgreSQL...${NC}"
yarn create strapi-app ./my-project --quickstart

# Configure environment variables for production
cd my-project
cat > .env << 'EOF'
HOST=0.0.0.0
PORT=1337
APP_KEYS=$(openssl rand -base64 32),$(openssl rand -base64 32)
API_TOKEN_SALT=$(openssl rand -base64 32)
ADMIN_JWT_SECRET=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)

# Database
DATABASE_CLIENT=postgres
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432
DATABASE_NAME=strapi
DATABASE_USERNAME=strapi
DATABASE_PASSWORD=strapipassword
DATABASE_SSL=false
EOF

# Install PM2 for process management
echo -e "\n${GREEN}Installing PM2 for process management...${NC}"
sudo npm install -g pm2

# Setup PM2 startup script
pm2 startup
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME

# Start Strapi with PM2
echo -e "\n${GREEN}Starting Strapi with PM2...${NC}"
pm2 start npm --name "strapi" -- run start
pm2 save

# Setup Nginx as a reverse proxy (optional)
echo -e "\n${GREEN}Installing Nginx as a reverse proxy...${NC}"
sudo apt-get install -y nginx

# Create Nginx configuration for Strapi
sudo tee /etc/nginx/sites-available/strapi << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:1337;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Enable the Nginx site
sudo ln -s /etc/nginx/sites-available/strapi /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

# Print summary
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}Strapi has been successfully installed!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "Strapi is running at: http://YOUR_SERVER_IP:1337"
echo -e "Admin panel: http://YOUR_SERVER_IP:1337/admin"
echo -e "\nPostgreSQL Database Information:"
echo -e "Database Name: strapi"
echo -e "Database User: strapi"
echo -e "Database Password: strapipassword"
echo -e "\nImportant directories:"
echo -e "Strapi project: ${STRAPI_PATH}/my-project"
echo -e "\nProcess Management:"
echo -e "View Strapi status: pm2 status"
echo -e "View Strapi logs: pm2 logs strapi"
echo -e "Restart Strapi: pm2 restart strapi"
echo -e "\n${YELLOW}Note: For production use, it's recommended to set up SSL/TLS with Let's Encrypt.${NC}"
echo -e "${YELLOW}You can use Certbot to automatically configure HTTPS.${NC}"
echo -e "${GREEN}==========================================${NC}"
