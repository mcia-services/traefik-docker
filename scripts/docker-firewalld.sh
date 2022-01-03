#!/bin/bash

if [ -x "$(command -v firewall-cmd)" ]; then
  echo "FirewallD is already installed"
else
  echo "Installing FirewallD..."
  # update/upgrade
  sudo apt update
  sudo apt upgrade --yes
  # install firewalld
  sudo apt install --yes firewalld
  # See https://www.putorius.net/introduction-to-firewalld-basics.html for config details or https://fedoraproject.org/wiki/Firewalld
fi

# make sure is started and enabled on boot
sudo systemctl enable firewalld
sudo systemctl start firewalld

# configure the rules for a public webserver
echo "Configuring firewall rules..."
sudo firewall-cmd --permanent --zone=public --set-target=REJECT
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --permanent --zone=public --add-interface=eth0

sudo firewall-cmd --reload

# Configure firewalld to remove the interface docker0 from the trusted zone (allow all traffic)
# Please substitute the appropriate zone and docker interface https://docs.docker.com/network/iptables/#integration-with-firewalld

# 1. Stop Docker
sudo systemctl stop docker

# 2. Recreate DOCKER-USER iptables chain in firewalld. Ignore any warnings
sudo firewall-cmd --permanent --direct --remove-chain ipv4 filter DOCKER-USER
sudo firewall-cmd --permanent --direct --remove-rules ipv4 filter DOCKER-USER
sudo firewall-cmd --permanent --direct --add-chain ipv4 filter DOCKER-USER
   
# 3. Add iptables rules to DOCKER-USER chain. Beware, the internal docker private network ip may change
sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -m conntrack \
  --ctstate RELATED,ESTABLISHED -j ACCEPT \
  -m comment --comment 'Allow containers to connect to the outside world'

sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -j RETURN \
  -s 172.17.0.0/16 \
  -m comment --comment 'allow internal docker communication'

sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -j RETURN \
  -s 172.18.0.0/16 \
  -m comment --comment 'allow internal docker communication, network: proxy'

# 4. Allow access to the Traefik ports
sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -o traefik-proxy \
  -p tcp -d 172.18.0.2 --dport 80 -j ACCEPT \
  -m comment --comment 'Allow all traffic to http docker port, traefik'

sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -o traefik-proxy \
  -p tcp -d 172.18.0.2 --dport 443 -j ACCEPT \
  -m comment --comment 'Allow all traffic to https docker port, traefik'

# 5. Block all other IPs. This rule has lowest precedence, so you can add rules before this one later.
sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 10 \
  -j REJECT -m comment --comment 'reject all other traffic to DOCKER-USER'

# 6. Activate rules
sudo firewall-cmd --reload

# 7. Start Docker
sudo systemctl start docker
