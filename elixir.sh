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

# Install multiple validator nodes without proxy check
function install_multiple_nodes() {
    check_and_install_python
    check_and_install_docker

    if [ ! -f "private_keys.txt" ] || [ ! -f "address.txt" ] || [ ! -f "username.txt" ] || [ ! -f "proxy.txt" ]; then
        echo "Required files (private_keys.txt, address.txt, username.txt, proxy.txt) not found."
        exit 1
    fi

    # Create a Docker bridge network (if not already created)
    if ! docker network ls | grep -q "elixir_net"; then
        echo "Creating Docker network elixir_net..."
        docker network create elixir_net
    fi

    # Read the files and store the data into arrays
    mapfile -t addresses < address.txt
    mapfile -t private_keys < private_keys.txt
    mapfile -t usernames < username.txt
    mapfile -t proxies < proxy.txt # Read proxies

    read -p "How many validator nodes would you like to create? " num_nodes

    if [ ${#addresses[@]} -lt $num_nodes ] || [ ${#private_keys[@]} -lt $num_nodes ] || [ ${#usernames[@]} -lt $num_nodes ]; then
        echo "Insufficient entries in input files for $num_nodes nodes."
        exit 1
    fi

    # Pull the latest Docker image before starting any containers
    echo "Pulling the latest Docker image for elixirprotocol/validator:v3..."
    docker pull elixirprotocol/validator:testnet

    # Prepare to run Docker containers
    for i in $(seq 1 $num_nodes); do
        validator_name=${usernames[$((i-1))]}
        safe_public_address=${addresses[$((i-1))]}
        private_key=${private_keys[$((i-1))]}
        random_proxy=${proxies[$((i-1))]}

        # Split the proxy into user, pass, IP, and port
        proxy_user=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 1)
        proxy_pass=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 2)
        proxy_ip=$(echo $random_proxy | cut -d "@" -f 2 | cut -d ":" -f 1)
        proxy_port=$(echo $random_proxy | cut -d ":" -f 3)

        # Create an .env file for each validator node
        cat <<EOF > validator_${i}.env
ENV=testnet-3
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
SIGNER_PRIVATE_KEY=${private_key}
PROXY_USER=${proxy_user}
PROXY_PASS=${proxy_pass}
PROXY_IP=${proxy_ip}
PROXY_PORT=${proxy_port}
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
    done

    echo "Successfully launched $num_nodes validator nodes with rotating proxies."
}

# Delete all Elixir Docker containers, their .env files, and images
function delete_docker_container() {
    # Fetch all containers with names matching 'elixir_'
    local containers_to_remove=$(docker ps -a --filter "name=elixir_" --format "{{.ID}}")

    if [ -z "$containers_to_remove" ]; then
        echo "No validator nodes to delete."
        exit 1
    else
        echo "Found validator nodes to delete."
    fi

    # Stop and remove containers
    echo "Stopping and removing all Elixir containers..."
    echo "$containers_to_remove" | xargs -r docker stop
    echo "$containers_to_remove" | xargs -r docker rm -f

    # Remove all related Elixir Docker images
    echo "Removing all related Elixir Docker images..."
    docker images --format '{{.Repository}}:{{.Tag}}' | grep 'elixirprotocol/validator:v3' | xargs -r docker rmi -f
    rm -rf validator_*.env
    echo "Cleanup complete."
}

# Update all created validator nodes
function update_all_nodes() {
    if [ ! -f "private_keys.txt" ] || [ ! -f "address.txt" ] || [ ! -f "username.txt" ] || [ ! -f "proxy.txt" ]; then
        echo "Required files (private_keys.txt, address.txt, username.txt, proxy.txt) not found."
        exit 1
    fi

    # Read the files and store the data into arrays
    mapfile -t addresses < address.txt
    mapfile -t private_keys < private_keys.txt
    mapfile -t usernames < username.txt
    mapfile -t proxies < proxy.txt # Read proxies

    # Get number of running validators
    num_nodes=$(docker ps -a --filter "name=elixir_" --format "{{.ID}}" | wc -l)

    if [ ${#addresses[@]} -lt $num_nodes ] || [ ${#private_keys[@]} -lt $num_nodes ] || [ ${#usernames[@]} -lt $num_nodes ]; then
        echo "Insufficient entries in input files for $num_nodes nodes."
        exit 1
    fi

    # Update running Docker containers
    for i in $(seq 1 $num_nodes); do
        validator_name=${usernames[$((i-1))]}

        # Kill the existing Docker container
        docker kill elixir_${i}

        # Remove the Docker container
        docker rm elixir_${i}

        # Rotate proxy: if all proxies are used, start again from the beginning
        proxy_index=$(( (i-1) % ${#proxies[@]} ))
        random_proxy=${proxies[$proxy_index]}

        # Split the proxy into user, pass, IP, and port
        proxy_user=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 1)
        proxy_pass=$(echo $random_proxy | cut -d "@" -f 1 | cut -d ":" -f 2)
        proxy_ip=$(echo $random_proxy | cut -d "@" -f 2 | cut -d ":" -f 1)
        proxy_port=$(echo $random_proxy | cut -d ":" -f 4)

        # Pull the latest Docker image
        docker pull elixirprotocol/validator:v3

        # Create an .env file for each validator node
        cat <<EOF > validator_${i}.env
ENV=testnet-3
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
SIGNER_PRIVATE_KEY=${private_key}
PROXY_USER=${proxy_user}
PROXY_PASS=${proxy_pass}
PROXY_IP=${proxy_ip}
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
          elixirprotocol/validator:testnet

        echo "Validator node ${validator_name} updated and restarted with proxy ${random_proxy}."
    done

    echo "Successfully updated $num_nodes validator nodes with rotating proxies."
}

# Main script functionality
function main_menu() {
    PS3='Please enter your choice: '
    options=("Install multiple validator nodes" "Update all validator nodes" "Delete all Docker containers" "Exit")
    select opt in "${options[@]}"; do
        case $opt in
            "Install multiple validator nodes")
                install_multiple_nodes
                ;;
            "Update all validator nodes")
                update_all_nodes
                ;;
            "Delete all Docker containers")
                delete_docker_container
                ;;
            "Exit")
                echo "Exiting..."
                break
                ;;
            *) echo "Invalid option $REPLY";;
        esac
    done
}

# Run the main menu
main_menu
