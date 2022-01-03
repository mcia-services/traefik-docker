#!/bin/bash

if [ -x "$(command -v fail2ban-client)" ]; then
  echo "Fail2ban is already installed"
else
  echo "Installing Fail2ban..."
  # update/upgrade
  sudo apt update
  sudo apt upgrade --yes
  # install fail2ban
  sudo apt install --yes fail2ban
fi

echo "Copying filters and jail files..."
# move the filter definition files to /etc/fail2ban/filter.d/
mv fail2ban/filter/* /etc/fail2ban/filter.d/

# copy the jail files to /etc/fail2ban/jail.d/
mv fail2ban/jail/* /etc/fail2ban/jail.d/

# restart fail2ban
echo "Restarting service..."
sudo service fail2ban restart
echo "Done"
