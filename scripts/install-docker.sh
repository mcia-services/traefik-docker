#!/bin/bash

# variables
DOCKER_WITHOUT_SUDO=0 # if 1, a docker group will be created and the user added. WARNING: this adds privileges like root
DOCKER_COMPOSE_VERSION=1.29.2
# docker daemon.json file, log rotation
DAEMON_FILE="{
  \"log-driver\": \"json-file\", 
  \"log-opts\": {
    \"max-size\": \"100m\",
    \"max-file\": \"5\"
  }
}"

# update/upgrade
sudo apt update
sudo apt upgrade --yes

# install docker engine 
# see Docker repository method 
# https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
echo "Installing docker engine..."

sudo apt install ca-certificates \
                 curl \
                 gnupg \
                 lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install --yes docker-ce docker-ce-cli containerd.io

# Setting the docker log rotation policy
echo "Setting the docker log rotation policy..."
sudo apt install --yes python
echo -e $DAEMON_FILE | python -m json.tool | sudo tee /etc/docker/daemon.json

# Install docker-compose
echo "Installing docker-compose..."

sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose
# sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose # symlink

if [[ $DOCKER_WITHOUT_SUDO -eq 1 ]]; then
echo "Creating a docker group to allow using docker without sudo"
  # create docker group
  sudo groupadd docker
  # add user to docker group
  sudo usermod -aG docker $USER
echo "A restart may be needed to revaluate user permissions"
fi
echo "Done"
