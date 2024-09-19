#!/bin/bash

# Ensure script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run with root user privileges."
    echo "Please try using 'sudo -i' to switch to the root user, and then run this script again."
    exit 1
fi

# Script save path
SCRIPT_PATH="$HOME/ElixirV3.sh"

# Variable to track how many validator nodes were created
NUM_VALIDATOR_NODES=0

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

    if ! python3 -c "import requests" &> /dev/null; then
        echo "Python 'requests' module not detected, installing..."
        pip3 install requests
        echo "'requests' module installed."
    else
        echo "'requests' module is already installed."
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

# Install multiple validator nodes
function install_multiple_nodes() {
    check_and_install_python
    check_and_install_docker

    if [ ! -f "private_keys.txt" ] || [ ! -f "address.txt" ] || [ ! -f "username.txt" ]; then
        echo "Required files (private_keys.txt, address.txt, username.txt) not found."
        exit 1
    fi

    mapfile -t addresses < address.txt
    mapfile -t private_keys < private_keys.txt
    mapfile -t usernames < username.txt

    read -p "How many validator nodes would you like to create? " num_nodes

    if [ ${#addresses[@]} -lt $num_nodes ] || [ ${#private_keys[@]} -lt $num_nodes ] || [ ${#usernames[@]} -lt $num_nodes ]; then
        echo "Insufficient entries in input files for $num_nodes nodes."
        exit 1
    fi

    for i in $(seq 1 $num_nodes); do
        validator_name=${usernames[$((i-1))]}
        safe_public_address=${addresses[$((i-1))]}
        private_key=${private_keys[$((i-1))]}

        cat <<EOF > validator_${i}.env
ENV=testnet-3
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
SIGNER_PRIVATE_KEY=${private_key}
EOF

        if [ $i -eq 1 ]; then
            docker pull elixirprotocol/validator:v3
        fi

        docker run -it -d --env-file validator_${i}.env --name elixir_${i} elixirprotocol/validator:v3
        echo "Validator node ${validator_name} started."
    done

    NUM_VALIDATOR_NODES=$num_nodes
}

# Delete all Elixir Docker containers and their .env files
function delete_docker_container() {
    NUM_VALIDATOR_NODES=$(ls validator_*.env 2>/dev/null | wc -l)

    if [ $NUM_VALIDATOR_NODES -eq 0 ]; then
        echo "No validator nodes to delete."
        exit 1
    fi

    for i in $(seq 1 $NUM_VALIDATOR_NODES); do
        container_name="elixir_${i}"

        # Check if the container exists
        container_id=$(docker ps -a -q --filter "name=${container_name}")
        if [ -z "$container_id" ]; then
            echo "No container found with name ${container_name}, skipping."
            continue
        fi

        echo "Stopping container ${container_name}..."
        if ! docker stop "$container_id"; then
            echo "Error stopping container ${container_name}, it might not be running."
        fi

        echo "Removing container ${container_name}..."
        if ! docker rm "$container_id"; then
            echo "Error removing container ${container_name}, it might have already been removed."
        fi

        env_file="validator_${i}.env"
        if [ -f "$env_file" ]; then
            echo "Removing environment file ${env_file}..."
            rm "$env_file"
        else
            echo "Environment file ${env_file} not found, skipping."
        fi
    done
    echo "Cleanup complete."
}

# Update all created validator nodes
function update_all_nodes() {
    NUM_VALIDATOR_NODES=$(ls validator_*.env 2>/dev/null | wc -l)

    if [ $NUM_VALIDATOR_NODES -eq 0 ]; then
        echo "No validator nodes to update."
        exit 1
    fi

    for i in $(seq 1 $NUM_VALIDATOR_NODES); do
        docker kill elixir_${i}
        docker rm elixir_${i}
        docker pull elixirprotocol/validator:v3
        docker run -it -d --env-file validator_${i}.env --name elixir_${i} elixirprotocol/validator:v3
        echo "Validator node $i updated and restarted."
    done
}

# View Docker logs for a specific container
function check_docker_logs() {
    read -p "Enter the container number (e.g., 1, 2): " container_number
    container_name="elixir_${container_number}"

    # Check if the container exists
    if docker ps -a --filter "name=${container_name}" --format '{{.Names}}' | grep -q "${container_name}"; then
        echo "Fetching logs for container ${container_name}..."
        docker logs "${container_name}"
    else
        echo "No container found with name ${container_name}."
    fi
}

# Main script functionality
function main_menu() {
    PS3='Please enter your choice: '
    options=("Install multiple validator nodes" "Update all validator nodes" "Delete all Docker containers" "Check Docker logs" "Exit")
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
            "Check Docker logs")
                check_docker_logs
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
