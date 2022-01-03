# Traefik Docker

This repository is intended to contain the information and workflows needed to configure a production server
with [Docker](https://www.docker.com/) and [Traefik](https://traefik.io/).

This production server is secured using a firewall and traefik as a reverse proxy.

## Firewall

This repository configures the firewall using [firewalld](https://www.firewalld.org/).
Firewalld is not the default firewall daemon for Ubuntu systems, but is the one that [seems to be supported](https://docs.docker.com/network/iptables/#integration-with-firewalld) by Docker.
> The usual firewall daemon for Ubuntu is Uncomplicated Firewall ([UFW](https://help.ubuntu.com/community/UFW)), but is is a [known issue](https://github.com/moby/moby/issues/4737) that docker does not play well with ufw. The common solution applied by many is to use the snippets in the [ufw-docker](https://github.com/chaifeng/ufw-docker) repository.

***
Currently, the issues with Docker and firewall frontends are not solved (neither with ufw nor with firewalld). [See here for an issue with Docker and firewalld](https://github.com/moby/moby/issues/22054). The main problem is that Docker modifies the firewall rules when it starts and stops containers, and these changes are made directly to the backend (iptables) making them invisible for firewalld or ufw. Additionally these rules are added to the `DOCKER` chain and are applied before the rules made by firewalld and ufw, hence proritizing them. From [docs](https://docs.docker.com/network/iptables/):

>Rules added to the `FORWARD` chain -- either manually, or by another iptables-based firewall -- are evaluated after these chains. This means that if you expose a port through Docker, this port gets exposed no matter what rules your firewall has configured

This is the expected behavior of the `--publish` option of docker run, from the docs:
> Note that ports which are not bound to the host (i.e., -p 80:80 instead of -p 127.0.0.1:80:80) will be accessible from the outside. This also applies if you configured UFW to block this specific port, as Docker manages his own iptables rules.

However, pointing to the localhost (i.e. 127.0.0.1), an attacker can still connect to the container by routing the packets through the victim's external IP. But it is a starting point.
Another valid approach is to use `expose` in docker-compose files, This makes the ports only accessible to linked containers.

There is not a current easy solution that has no drawbacks:

### Solution 1: Overkillingly use `iptables`

To ensure your docker containers are protected by your firewall rules: run your images with the --network host option and set `{ "iptables": false }` in `/etc/docker/daemon.json` (Note, you will need to both run systemctl restart docker and reset iptables, firewalld-cmd --reload on CentOS, for these changes to take affect, restarting will also work)

This will have two very important affects:

- If you forget to run your docker image with --network host then they won't be accessible to the outside world, but will themselves not be able to make external network requests. (That is the effect of `{ "iptables": false }`)
- Your docker containers will be constrained by your normal firewall rules set by firewalld, ufw or your tool of choice, since your docker containers are using your host's network.
  
Therefore, this bypasses docker's entire network setup and exposing the ports to the ouside should be done in a container per container basis. will more than likely break container networking for the Docker engine.

### Solution 2: Write iptables rules directly into `DOCKER-USER` chain

This solution is a little bit less agressive with docker's networking configuration. It essentially establish a set of rules in a chain before the rules made by docker, blocking the outside traffic.
This is the solution used by `docker-ufw`.
To enable any port it should be opened manually using dedicated rules. However, the port to state is the target NAT port (i.e. the Docker Container port) and not the NAT source port (i.e. the port exposed to the outside world). So for example, if you have a service exposed as `--publish 8080:80`, you should allow traffic to port `80` in your firewall rules.

**Warning** This, however, open all the external ports that have an internal `80` port published. To only open the port of a specific container, you should add the container ip to the rule.

This is the solution used and the details are explained in the section below

***

### Firewalld Configuration

The firewall rules are specified in the `docker-firewalld.sh` script. It basically only allows the traffic through ports 80 and 443. The rest of ports are blocked blocked.
To understand how firewalld works (zones, services, permanent vs runtime, etc.), please refer to the [firewalld documentation](https://www.firewalld.org/docs/firewalld-manual.html), [firewalld basics](https://www.putorius.net/introduction-to-firewalld-basics.html) or [Fedora Firewalld](https://fedoraproject.org/wiki/Firewalld).

As Docker bypasses the rules above, new rules added directly to iptables have to be used. Using the firewalld commands described in this [tutorial](https://roosbertl.blogspot.com/2019/06/securing-docker-ports-with-firewalld.html), we can block the external traffic to the docker containers. See the `docker-firewalld.sh` script for the details. The `/etc/firewalld/direct.xml` file looks like this:

```xml
<?xml version="1.0" encoding="utf-8"?>
<direct>
  <chain table="filter" ipv="ipv4" chain="DOCKER-USER"/>
  <rule priority="1" table="filter" ipv="ipv4" chain="DOCKER-USER">-m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment 'Allow docker containers to connect to the outside world'</rule>
  <rule priority="1" table="filter" ipv="ipv4" chain="DOCKER-USER">-j RETURN -s 172.17.0.0/16 -m comment --comment 'allow internal docker communication'</rule>
  <rule priority="10" table="filter" ipv="ipv4" chain="DOCKER-USER">-j REJECT -m comment --comment 'reject all other traffic to DOCKER-USER'</rule>
    <rule ipv="ipv4" table="filter" chain="DOCKER-USER" priority="1">-o traefik-proxy -p tcp -d 172.18.0.2 --dport 80 -j ACCEPT -m comment --comment 'Allow all traffic to http docker port, traefik'</rule>
  <rule ipv="ipv4" table="filter" chain="DOCKER-USER" priority="1">-o traefik-proxy -p tcp -d 172.18.0.2 --dport 443 -j ACCEPT -m comment --comment 'Allow all traffic to https docker port, traefik'</rule>
</direct>
```

The communication for the traefik proxy network and the traffic through external http and https ports are already enabled.

To add a new port use the following command:
```
firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -o <interface> \
  -p tcp --dport 80 -j ACCEPT \
  -m comment --comment 'Allow all traffic to http docker port'
```

This command opens all the external ports that have an internal `80` port published. To open only a specific container port, you should add the container ip (find it using `docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' container_name_or_id`) to the rule:
```
firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 1 \
  -o <interface> \
  -p tcp -d 172.17.0.3 --dport 80 -j ACCEPT \
  -m comment --comment 'Allow all traffic to http docker port'
```

In both commands replace `<interface>` with the network interface you want to use (the default `docker0` or if you create any network, the network interface name).
In 
### Fail2Ban

[Fail2Ban](https://www.fail2ban.org/) is a security tool that monitors the logs of a server and detects suspicious activity. Then it updates the firewall rules to reject IP adresses for a specified amount of time.

To configure Fail2Ban, the [following tutorial](https://geekland.eu/usar-fail2ban-con-traefik-para-proteger-servicios-que-corren-en-docker/) will be followed.
The starting configuration covers banning the unauthorized attempts to login through the traefik web interface.
To add more services, just create new files in fail2ban [filter](./scripts/fail2ban/filter) and jail[jail](./scripts/fail2ban/jail) folders.

## How to deploy 

1. Run the `scripts/install-docker.sh` script to install docker and docker-compose. Additionally, a group named `docker` can be created and the user added to it to execute the docker command without `sudo`.
2. Run `traefik/deploy-traefik.sh` to deploy traefik. This scripts has 3 optional arguments:
   - `-u`: username for the basic-auth in the dashboard web interface.
   - `-p`: password for the basic-auth in the dashboard web interface.
   - `-e`: email for the letsencrypt certificate.
3. `cd` to `scripts` folder and run `docker-firewalld.sh` and `configure-fail2ban.sh` to configure the firewall rules and fail2ban.

Then, the server is ready to deploy any new service. See an example `docker-compose.yml` file in the `examples` folder.