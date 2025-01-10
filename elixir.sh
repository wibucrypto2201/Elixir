#!/bin/bash

# Ensure script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run with root user privileges."
    echo "Please try using 'sudo -i' to switch to the root user, and then run this script again."
    exit 1
fi

# Check and install Python 3 and dependencies
function check_and_install_python() {
    if ! command -v python3 &> /dev/null; then
        echo "Python 3 not detected, installing..."
        sudo apt-get update
        sudo apt-get install -y python3
        echo "Python 3 installed."
    else
        echo "Python 3 is already installed."
    fi

    if ! command -v pip3 &> /dev/null; then
        echo "pip for Python 3 not detected, installing..."
        sudo apt-get install -y python3-pip
        echo "pip installed."
    else
        echo "pip is already installed."
    fi
}

# Check and install Docker
function check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not detected, installing..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce
        echo "Docker installed."
    else
        echo "Docker is already installed."
    fi
}

# Function to check if the proxy is working
# Function to check if the proxy is working
function check_proxy() {
    local proxy=$1
    local target_url="https://api.testnet-3.elixir.xyz/"
    
    echo "Testing proxy: $proxy"
    
    # Set a retry count and timeout for the proxy check
    local retry_count=3
    local retry_delay=5
    local connect_timeout=5
    
    for attempt in $(seq 1 $retry_count); do
        # Use curl to check if the proxy can connect (with timeout and retries)
        curl -x "http://${proxy}" --connect-timeout $connect_timeout -s $target_url > /dev/null
        
        if [ $? -eq 0 ]; then
            echo "Proxy $proxy is working."
            return 0
        else
            echo "Proxy $proxy failed on attempt $attempt of $retry_count."
            sleep $retry_delay
        fi
    done
    
    echo "Proxy $proxy failed after $retry_count attempts. Skipping..."
    return 1
}
# Install multiple validator nodes with rotating proxies and proxy check
# Install multiple validator nodes without proxy check
function install_multiple_nodes() {
    check_and_install_python
    check_and_install_docker
@@ -112,21 +81,16 @@
        validator_name=${usernames[$((i-1))]}
        safe_public_address=${addresses[$((i-1))]}
        private_key=${private_keys[$((i-1))]}
        random_proxy=${proxies[$((i-1))]}

        # Rotate proxy: if all proxies are used, start again from the beginning
        proxy_index=$(( (i-1) % ${#proxies[@]} ))
        random_proxy=${proxies[$proxy_index]}
        # Check if the proxy works
        if check_proxy $random_proxy; then
            # Split the proxy into user, pass, IP, and port
            proxy_user=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 1)
            proxy_pass=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 2)
            proxy_ip=$(echo $random_proxy | cut -d "@" -f 2 | cut -d ":" -f 1)
            proxy_port=$(echo $random_proxy | cut -d ":" -f 3)
        # Split the proxy into user, pass, IP, and port
        proxy_user=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 1)
        proxy_pass=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 2)
        proxy_ip=$(echo $random_proxy | cut -d "@" -f 2 | cut -d ":" -f 1)
        proxy_port=$(echo $random_proxy | cut -d ":" -f 3)

            # Create an .env file for each validator node
            cat <<EOF > validator_${i}.env
        # Create an .env file for each validator node
        cat <<EOF > validator_${i}.env
ENV=testnet-3
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
@@ -138,20 +102,17 @@
STRATEGY_EXECUTOR_IP_ADDRESS=${proxy_ip}
EOF

            # Run the Docker container with --restart unless-stopped and attach to Docker network
            docker run -d \
              --env-file validator_${i}.env \
              --name elixir_${i} \
              --network elixir_net \
              --restart unless-stopped \
              -e http_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
              -e https_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
              elixirprotocol/validator:v3
            echo "Validator node ${validator_name} started with proxy ${random_proxy}."
        else
            echo "Skipping validator node ${validator_name} due to failed proxy."
        fi
        # Run the Docker container with --restart unless-stopped and attach to Docker network
        docker run -d \
          --env-file validator_${i}.env \
          --name elixir_${i} \
          --network elixir_net \
          --restart unless-stopped \
          -e http_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
          -e https_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
          elixirprotocol/validator:v3
        echo "Validator node ${validator_name} started with proxy ${random_proxy}."
    done

    echo "Successfully launched $num_nodes validator nodes with rotating proxies."
@@ -181,9 +142,6 @@
    echo "Cleanup complete."
}

# Update all
# Update all created validator nodes
function update_all_nodes() {
    if [ ! -f "private_keys.txt" ] || [ ! -f "address.txt" ] || [ ! -f "username.txt" ] || [ ! -f "proxy.txt" ]; then
@@ -219,19 +177,17 @@
        proxy_index=$(( (i-1) % ${#proxies[@]} ))
        random_proxy=${proxies[$proxy_index]}

        # Check if the proxy works
        if check_proxy $random_proxy; then
            # Split the proxy into user, pass, IP, and port
            proxy_user=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 1)
            proxy_pass=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 2)
            proxy_ip=$(echo $random_proxy | cut -d "@" -f 2 | cut -d ":" -f 1)
            proxy_port=$(echo $random_proxy | cut -d ":" -f 4)
        # Split the proxy into user, pass, IP, and port
        proxy_user=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 1)
        proxy_pass=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 2)
        proxy_ip=$(echo $random_proxy | cut -d "@" -f 2 | cut -d ":" -f 1)
        proxy_port=$(echo $random_proxy | cut -d ":" -f 4)

            # Pull the latest Docker image
            docker pull elixirprotocol/validator:v3
        # Pull the latest Docker image
        docker pull elixirprotocol/validator:v3

            # Create an .env file for each validator node
            cat <<EOF > validator_${i}.env
        # Create an .env file for each validator node
        cat <<EOF > validator_${i}.env
ENV=testnet-3
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
@@ -242,20 +198,17 @@
PROXY_PORT=${proxy_port}
EOF

            # Restart the container with the latest image and attach to Docker network
            docker run -d \
              --env-file validator_${i}.env \
              --name elixir_${i} \
              --network elixir_net \
              --restart unless-stopped \
              -e http_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
              -e https_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
              elixirprotocol/validator:v3
            echo "Validator node ${validator_name} updated and restarted with proxy ${random_proxy}."
        else
            echo "Skipping validator node ${validator_name} due to failed proxy."
        fi
        # Restart the container with the latest image and attach to Docker network
        docker run -d \
          --env-file validator_${i}.env \
          --name elixir_${i} \
          --network elixir_net \
          --restart unless-stopped \
          -e http_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
          -e https_proxy="http://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}" \
          elixirprotocol/validator:v3
        echo "Validator node ${validator_name} updated and restarted with proxy ${random_proxy}."
    done

    echo "Successfully updated $num_nodes validator nodes with rotating proxies."
