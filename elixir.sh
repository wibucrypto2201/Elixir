#!/bin/bash

# Check if the script is run as root user
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run with root privileges."
    echo "Please try using 'sudo -i' to switch to the root user, and then run this script again."
    exit 1
fi

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

# Load data from files
function load_data() {
    if [[ ! -f username.txt || ! -f private_keys.txt || ! -f address.txt || ! -f proxy.txt ]]; then
        echo "One or more required files (username.txt, private_keys.txt, address.txt, proxy.txt) are missing."
        exit 1
    fi

    mapfile -t usernames < username.txt
    mapfile -t private_keys < private_keys.txt
    mapfile -t addresses < address.txt
    mapfile -t proxies < proxy.txt

    if [[ ${#usernames[@]} -ne ${#private_keys[@]} || ${#usernames[@]} -ne ${#addresses[@]} ]]; then
        echo "The files username.txt, private_keys.txt, and address.txt must have the same number of lines."
        exit 1
    fi
}

# Run multiple Docker containers
function run_multiple_containers() {
    load_data

    read -p "Enter the number of validator Docker containers to run: " num_validators

    for ((i = 0; i < num_validators; i++)); do
        index=$((i % ${#usernames[@]}))      # Get index for usernames, private keys, addresses
        proxy_index=$((i % ${#proxies[@]}))  # Get index for proxies (circular)

        username=${usernames[$index]}
        private_key=${private_keys[$index]}
        address=${addresses[$index]}
        proxy=${proxies[$proxy_index]}

        # Save environment variables to a unique validator.env file
        env_file="validator_$i.env"
        cat <<EOF > $env_file
ENV=prod
STRATEGY_EXECUTOR_IP_ADDRESS=${proxy}
STRATEGY_EXECUTOR_DISPLAY_NAME=${username}
STRATEGY_EXECUTOR_BENEFICIARY=${address}
SIGNER_PRIVATE_KEY=${private_key}
EOF

        echo "Starting Docker container for validator $i with username: $username, address: $address, proxy: $proxy..."

        # Run the Docker container
        docker run -d \
          -p $((17690 + i)):17690 \
          --env-file $env_file \
          --name elixir_$i \
          --restart unless-stopped \
          elixirprotocol/validator:testnet
    done
}

# Delete all Docker containers created by this script
function delete_all_containers() {
    echo "Stopping and deleting all Elixir Docker containers..."
    for container in $(docker ps -a --filter "name=elixir_" --format "{{.ID}}"); do
        docker stop "$container"
        docker rm "$container"
    done
    echo "All Elixir Docker containers have been deleted."
}

# Main menu
function main_menu() {
    check_and_install_docker

    clear
    echo "===================== Elixir V3 Node Installation ========================="
    echo "1. Run multiple Docker containers"
    echo "2. Delete all Docker containers"
    read -p "Enter your choice (1-2): " OPTION

    case $OPTION in
    1) run_multiple_containers ;;
    2) delete_all_containers ;;
    *) echo "Invalid option." ;;
    esac
}

# Display main menu
main_menu
