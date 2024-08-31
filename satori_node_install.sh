#!/bin/bash

# Function to display error messages and exit
error_exit() {
    echo "❌ Error: $1" >&2
    echo
    exit 1
}

# Function to display success messages
success_message() {
    echo "✅ Success: $1"
    echo
}

# Function to check if a command was successful
check_success() {
    if [ $? -ne 0 ]; then
        error_exit "$1"
    fi
}

# Function to check if a package is installed
is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to check if a group exists
group_exists() {
    getent group "$1" >/dev/null 2>&1
}

# Function to check if a service exists and is active
service_active() {
    systemctl is-active --quiet "$1"
}

##########################################
# ROOT PASSWORD CHANGE
##########################################

# echo -n "🔐 Do you want to change the root password? (y/n): "
# read change_passwd
# echo

# if [ "$change_passwd" = "y" ] || [ "$change_passwd" = "Y" ]; then
#     echo "⌛️ Changing root password..."
#     echo
    
#     # Prompt for new password
#     echo -n "Enter new root password: "
#     read -s new_passwd
#     echo
#     echo -n "Confirm new root password: "
#     read -s confirm_passwd
#     echo
#     echo

#     # Check if passwords match
#     if [ "$new_passwd" = "$confirm_passwd" ]; then
#         # Change the password
#         echo "root:$new_passwd" | sudo chpasswd
#         if [ $? -eq 0 ]; then
#             success_message "Root password changed successfully."
#         else
#             echo "❌ Failed to change root password. Please try again manually."
#             echo
#         fi
#     else
#         echo "⚠️ Passwords do not match. Root password not changed."
#         echo
#     fi
# else
#     echo "⌛️ Skipping root password change."
#     echo
# fi

##########################################
# UPDATE AND INSTALL PACKAGES
##########################################

# Update package lists
echo "⌛️ Updating package lists..."
echo
sudo apt-get update
check_success "Failed to update package lists."

# Install required packages
echo "⌛️ Installing required packages..."
echo
sudo apt-get install -y ca-certificates curl unzip
check_success "Failed to install required packages."

##########################################
# DOCKER INSTALLATION
##########################################

# Check if Docker is already installed
if ! command -v docker &> /dev/null; then
    echo "⌛️ Installing Docker..."
    echo
    
    # Add Docker's GPG key
    echo "⌛️ Adding Docker's GPG key..."
    echo
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    check_success "Failed to download Docker's GPG key."
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    check_success "Failed to set permissions on Docker's GPG key."

    # Add Docker repository
    echo "⌛️ Adding Docker repository..."
    echo
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_success "Failed to add Docker repository."

    # Update package lists again
    echo "⌛️ Updating package lists with Docker repository..."
    echo
    sudo apt-get update
    check_success "Failed to update package lists with Docker repository."

    # Install Docker
    echo "⌛️ Installing Docker..."
    echo
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_success "Failed to install Docker."

    # Verify Docker installation
    echo "⌛️ Verifying Docker installation..."
    echo
    sudo docker run hello-world
    check_success "Docker installation verification failed."
else
    echo "✅ Docker is already installed. Checking Docker service..."
    echo
    if service_active docker; then
        echo "✅ Docker service is active."
        echo
    else
        echo "⌛️ Docker service is not active. Starting Docker..."
        echo
        sudo systemctl start docker
        check_success "Failed to start Docker service."
    fi
fi

##########################################
# SATORI INSTALLATION
##########################################

# Check if Satori zip file needs to be downloaded and extracted
if [ ! -d ~/.satori ]; then
    if [ ! -f ~/satori.zip ]; then
        echo "⌛️ Downloading Satori..."
        echo
        wget -P ~/ https://satorinet.io/static/download/linux/satori.zip
        check_success "Failed to download Satori."
    else
        echo "✅ Satori zip file already exists. Skipping download."
        echo
    fi

    echo "⌛️ Extracting Satori..."
    echo
    unzip ~/satori.zip
    check_success "Failed to unzip Satori."
    rm ~/satori.zip
fi

# Ensure we're in the correct directory
cd ~/.satori || error_exit "Failed to change directory to ~/.satori"

# Install python3-venv if not already installed
if ! is_installed python3-venv; then
    echo "⌛️ Installing python3-venv..."
    echo
    sudo apt-get install -y python3-venv
    check_success "Failed to install python3-venv."
    sleep 1
else
    echo "✅ python3-venv is already installed. Skipping installation."
    echo
fi

# Ensure Docker group exists and user is a member
if ! getent group docker > /dev/null 2>&1; then
    echo "⌛️ Creating docker group..."
    echo
    sudo groupadd docker
fi

if ! groups $USER | grep &>/dev/null '\bdocker\b'; then
    echo "⌛️ Adding current user to docker group..."
    echo
    sudo usermod -aG docker $USER
    echo "⚠️ User added to docker group. Changes will take effect after logging out and back in."
    echo
    echo "⚠️ Continuing with the installation, but you may need to run the script again after re-logging."
    echo
fi

# Ensure we're in the correct directory
cd ~/.satori || error_exit "Failed to change directory to ~/.satori"

# Run Satori install script
echo "⌛️ Running Satori install script..."
echo
bash install.sh
check_success "Failed to run Satori install script."
sleep 3

# Run Satori service install script
echo "⌛️ Running Satori service install script..."
echo
if [ -f install_service.sh ]; then
    bash install_service.sh
    INSTALL_SERVICE_EXIT_CODE=$?
    if [ $INSTALL_SERVICE_EXIT_CODE -eq 0 ]; then
        echo "✅ Satori service installation script completed."
        echo
    else
        echo "⚠️ Satori service installation script encountered issues (Exit code: $INSTALL_SERVICE_EXIT_CODE)."
        echo
        echo "⚠️ This might be due to Docker group changes not taking effect."
        echo
        echo "⚠️ Please log out, log back in, and run this script again."
        echo
        exit 1
    fi
else
    error_exit "install_service.sh not found in ~/.satori directory."
fi

sleep 3

# Verify Satori service status
if systemctl is-active --quiet satori; then
    echo "✅ Satori service is active."
    echo
else
    echo "⚠️ Satori service is not active. Attempting to start Satori..."
    echo
    sudo systemctl start satori
    if systemctl is-active --quiet satori; then
        echo "✅ Satori service started successfully."
        echo
    else
        error_exit "Failed to start Satori service. Please check the logs and try again."
    fi
fi

cd


##########################################
# FAIL2BAN INSTALLATION
##########################################

# Install Fail2Ban
echo "⌛️ Installing Fail2Ban..."
echo
sudo apt install fail2ban -y

# Create a backup of the original jail.conf file
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.conf.backup

# Create SSH jail configuration
echo "⌛️ Configuring Fail2Ban SSH protection..."
echo
cat << EOF | sudo tee /etc/fail2ban/jail.d/sshd.conf
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
findtime = 300
bantime = 3600
banaction = iptables-multiport

# Only allow 3 retry
# 5 minutes
# 1 hour
EOF

# Restart Fail2Ban to apply changes
echo "⌛️ Restarting Fail2Ban..."
echo
sudo systemctl restart fail2ban
sleep 1

# Enable Fail2Ban to start on boot
echo "⌛️ Enabling Fail2Ban to start on boot..."
echo
sudo systemctl enable fail2ban
sleep 1

echo "✅ Fail2Ban has been installed and enhanced SSH protection has been configured."
echo


##########################################
# FAIL2BAN SETUP to protect neuron dashboard
##########################################

#!/bin/bash

# Define paths
SATORI_CONFIG_FILE=~/.satori/config/config.yaml
DEFAULT_LOG_DIR=~/scripts

# Function to safely update YAML config
update_yaml_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="$3"
    
    if grep -q "^$config_key:" "$config_file"; then
        sed -i "s|^$config_key:.*|$config_key: $config_value|" "$config_file"
    else
        echo "$config_key: $config_value" >> "$config_file"
    fi
}

# Function for user messages
display_message() {
    local message_text="$1"
    echo "$message_text"
    sleep 1
}

# 1. Check and update Satori config
if [ ! -f "$SATORI_CONFIG_FILE" ]; then
    display_message "Error: Satori config file not found at $SATORI_CONFIG_FILE. Exiting."
    exit 1
fi

# Check if fail2ban_log is already set
current_log_dir=$(grep "^fail2ban_log:" "$SATORI_CONFIG_FILE" | awk '{print $2}')
if [ -z "$current_log_dir" ]; then
    display_message "Setting fail2ban_log in Satori configuration..."
    update_yaml_config "fail2ban_log" "$DEFAULT_LOG_DIR" "$SATORI_CONFIG_FILE"
    LOG_DIR="$DEFAULT_LOG_DIR"
else
    display_message "fail2ban_log is already set to $current_log_dir"
    LOG_DIR="$current_log_dir"
fi

# 2. Create the log directory if it doesn't exist
display_message "Ensuring log directory exists..."
mkdir -p "$LOG_DIR"
if [ $? -eq 0 ]; then
    display_message "Log directory confirmed at $LOG_DIR."
else
    display_message "Error: Failed to create log directory. Exiting."
    exit 1
fi

# 3. Create fail2ban filter
display_message "Creating fail2ban filter..."
sudo tee /etc/fail2ban/filter.d/satori-auth.conf > /dev/null <<EOL
[Definition]
failregex = Failed login attempt \| IP: <HOST>
ignoreregex =
EOL
if [ $? -eq 0 ]; then
    display_message "Fail2ban filter created successfully."
else
    display_message "Error: Failed to create fail2ban filter. Exiting."
    exit 1
fi


echo "✅ Satori node installation and checks complete."
echo
# Get the IP address
IP=$(hostname -I | awk '{print $1}')
echo "$IP"
echo
# Display the dashboard URL
echo "✅ Node dashboard URL: http://$IP:24601"

echo "⚠️ Remeber to access your dashboard ASAP, then create your Vault (check the 'mine to vault' option) and finally lock your neuron from the dashboard"


# Uncomment the following lines if you want to reboot after installation
# echo "⚠️ System will reboot in 3 seconds..."
# echo
# sleep 3
# sudo reboot
