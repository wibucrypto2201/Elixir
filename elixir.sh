#!/bin/bash

# Check if the script is run as root user
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run with root user privileges."
    echo "Please try using 'sudo -i' to switch to the root user, and then run this script again."
    exit 1
fi

# Script save path
SCRIPT_PATH="$HOME/ElixirV3.sh"

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

    # Check and install pip for Python 3
    if ! command -v pip3 &> /dev/null; then
        echo "pip for Python 3 not detected, installing..."
        sudo apt-get install -y python3-pip
        echo "pip installed."
    else
        echo "pip is already installed."
    fi

    # Install requests library using pip
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

# Fetch a random username from randomuser.me API using Python
function fetch_random_username() {
    python3 - <<END
import requests
import sys
try:
    response = requests.get("https://randomuser.me/api/0.8/?results=1")
    if response.status_code == 200:
        username = response.json()["results"][0]["user"]["username"]
        print(username)
    else:
        sys.exit(1)
except Exception as e:
    sys.exit(1)
END
}

# Node installation function for multiple wallets (200 nodes)
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

    # Read addresses and private keys from files
    mapfile -t addresses < address.txt
    mapfile -t private_keys < private_keys.txt

    # Check if there are at least 200 addresses and private keys
    if [ ${#addresses[@]} -lt 200 ] || [ ${#private_keys[@]} -lt 200 ]; then
        echo "There must be at least 200 entries in both address.txt and private_keys.txt."
        exit 1
    fi

    # Loop through and install 200 nodes
    for i in {1..200}; do
        echo "Setting up validator node $i..."

        # Fetch a random username for each validator
        validator_name=$(fetch_random_username)
        if [ -z "$validator_name" ]; then
            echo "Failed to fetch random username. Exiting."
            exit 1
        fi

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
}

# View Docker logs function
function check_docker_logs() {
    echo "Viewing Elixir Docker container logs..."
    docker logs -f elixir
}

# Delete Docker container function
function delete_docker_container() {
    echo "Deleting Elixir Docker container..."
    docker stop elixir
    docker rm elixir
    echo "Elixir Docker container deleted."
}

# Option 5: Update all 200 validator nodes
function update_all_nodes() {
    echo "Updating all 200 validator nodes..."
    
    # Loop through all 200 nodes and update them
    for i in {1..200}; do
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
    echo "4. Install 200 Elixir V3 Nodes from private_keys.txt"
    echo "5. Update all 200 validator nodes"
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
