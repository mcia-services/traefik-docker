#!/bin/bash

username="admin"
password="admin"

while getopts u:p:e: flag
do
    case "${flag}" in
        u) username=${OPTARG};;
        p) password=${OPTARG};;
        e) email=${OPTARG};;
    esac
done

if [[ $username == "admin" && $password == "admin" ]]; then
    echo "Warning! Using the default admin:admin credentials"
fi


# 1 Creating the traefik credentials
if [ ! -x "$(command -v htpasswd)" ]; then
  echo "Installing apache2-utils for credentials creation"
  sudo apt install --yes apache2-utils
fi
credentials=$(htpasswd -nb $username $password)

# 2 Modifying the traefik configuration to add email and credentials
if [ ! -x "$(command -v yq)" ]; then
  echo "Installing yq to modify yaml files"
  VERSION=v4.2.0
  BINARY=yq_linux_amd64
  wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq
fi
yq e -i --null-input '.certificateResolvers.letsencrypt.acme.email = "'${email}'"' traefik.yml
yq e -i --null-input '.http.middlewares.user-auth.basicAuth.users[0] = "'${credentials}'"' configurations/dynamic.yml

# 3 Create the docker network
sudo docker network create --subnet 172.18.0.0/16 --opt com.docker.network.bridge.name=traefik-proxy proxy

# 4 create and correct permisions to the acme.json file
mkdir letsencrypt
touch acme.json
chmod 600 ./traefik-config/acme.json

# 5 Run the stack
sudo docker-compose up --detach
