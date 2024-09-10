#!/bin/bash

# Check if the script is run as root user
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run with root user privileges."
    echo "Please try using 'sudo -i' to switch to the root user, and then run this script again."
    exit 1
fi

# Script save path
SCRIPT_PATH="$HOME/ElixirV3.sh"

# Variable to track how many validator nodes were created
NUM_VALIDATOR_NODES=0

# Check and install Python 3
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

# Node installation function for multiple wallets
function install_multiple_nodes() {
    check_and_install_python
    check_and_install_docker

    # Ensure the required files exist
    if [ ! -f "private_keys.txt" ]; then
        echo "File private_keys.txt not found. Please make sure the file exists."
        exit 1
    fi
    if [ ! -f "address.txt" ]; then
        echo "File address.txt not found. Please make sure the file exists."
        exit 1
    fi
    if [ ! -f "username.txt" ]; then
        echo "File username.txt not found. Please make sure the file exists."
        exit 1
    fi

    # Read addresses, private keys, and usernames from files
    mapfile -t addresses < address.txt
    mapfile -t private_keys < private_keys.txt
    mapfile -t usernames < username.txt

    # Ask the user how many validator nodes to create
    read -p "How many validator nodes would you like to create? " num_nodes

    # Check if there are enough addresses, private keys, and usernames
    if [ ${#addresses[@]} -lt $num_nodes ] || [ ${#private_keys[@]} -lt $num_nodes ] || [ ${#usernames[@]} -lt $num_nodes ]; then
        echo "There must be at least $num_nodes entries in address.txt, private_keys.txt, and username.txt."
        exit 1
    fi

    # Loop through and install the requested number of nodes
    for i in $(seq 1 $num_nodes); do
        echo "Setting up validator node $i..."

        # Get username for each validator from the username.txt file
        validator_name=${usernames[$((i-1))]}

        # Get safe public address and private key
        safe_public_address=${addresses[$((i-1))]}
        private_key=${private_keys[$((i-1))]}

        # Create a unique environment file for each validator
        cat <<EOF > validator_${i}.env
ENV=testnet-3

STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
SIGNER_PRIVATE_KEY=${private_key}
EOF

        echo "Environment variables set and saved to validator_${i}.env file."

        # Pull Docker image for the first run
        if [ $i -eq 1 ]; then
            docker pull elixirprotocol/validator:v3
        fi

        # Run Docker container for each validator
        docker run -it -d \
          --env-file validator_${i}.env \
          --name elixir_${i} \
          elixirprotocol/validator:v3
        
        echo "Validator node ${validator_name} started with container elixir_${i}."
    done

    # Update the global variable with the number of validator nodes created
    NUM_VALIDATOR_NODES=$num_nodes
}

# View Docker logs function
function check_docker_logs() {
    echo "Viewing Elixir Docker container logs..."
    docker logs -f elixir
}

# Delete Docker container function
function delete_docker_container() {
    for i in $(seq 1 $NUM_VALIDATOR_NODES); do
        echo "Deleting Elixir Docker container..."
        docker stop elixir_${i}
        docker rm elixir_${i}
        echo "Elixir Docker container deleted."
    done
}

# Option 5: Update all created validator nodes
function update_all_nodes() {
    if [ $NUM_VALIDATOR_NODES -eq 0 ]; then
        echo "No validator nodes have been created yet."
        exit 1
    fi

    echo "Updating all $NUM_VALIDATOR_NODES validator nodes..."
    
    # Loop through all created nodes and update them
    for i in $(seq 1 $NUM_VALIDATOR_NODES); do
        echo "Updating validator node $i..."

        # Stop and remove the existing container
        docker kill elixir_${i}
        docker rm elixir_${i}

        # Pull the latest image
        docker pull elixirprotocol/validator:v3

        # Run the updated container with the respective environment file
        docker run -it -d \
          --env-file validator_${i}.env \
          --name elixir_${i} \
          elixirprotocol/validator:v3
        
        echo "Validator node $i has been updated and restarted."
    done
}

# Main menu
function main_menu() {
    clear
    echo "=====================Elixir V3 Node========================="
    echo "Please choose an operation to perform:"
    echo "1. Install Elixir V3 Node"
    echo "2. View Docker Logs"
    echo "3. Delete Elixir Docker Container"
    echo "4. Install Elixir V3 Nodes from private_keys.txt"
    echo "5. Update all created validator nodes"
    read -p "Please enter an option (1-5): " OPTION

    case $OPTION in
    1) install_node ;;
    2) check_docker_logs ;;
    3) delete_docker_container ;;
    4) install_multiple_nodes ;;
    5) update_all_nodes ;;
    *) echo "Invalid option." ;;
    esac
}

# Display main menu
main_menu
