#!/bin/bash

# this script will setup a Jitsi Meet docker container

# Setting Firewall rules
sudo ufw enable
# allow ssh (or else you can lock yourself out of the server)
sudo ufw allow in ssh
# allow HTTP, HTTPS and UDP range 10000:20000
sudo ufw allow in 80/tcp
sudo ufw allow in 443/tcp
sudo ufw allow in 4443/tcp
sudo ufw allow in 10000:20000/udp

# Clone this repository to your own computer.
cd ~
git clone https://github.com/jitsi/docker-jitsi-meet && cd docker-jitsi-meet

# Create an .env file
cp env.example .env
mkdir -p ~/.jitsi-meet-cfg/{web/letsencrypt,transcripts,prosody,jicofo,jvb}

# Settings variables
read -p 'What is the FQDN? ' varFQDN
read -p 'What is the mailadres for corresponding? ' varEmail

# Setup certificate
read -p "Use Let's Encrypt certificate?" varCert
if [[ $varCert =~ [yYnN] ]]; then
	if [[ $varCert =~ [yY] ]]; then
		echo "Enabling Let's Encrypt settings in .env file"
		sed -i 's/#HTTP_PORT=8000/HTTP_PORT=80/g' /home/$USER/docker-jitsi-meet/.env
		sed -i 's/#HTTPS_PORT=443/HTTPS_PORT=443/g' /home/$USER/docker-jitsi-meet/.env
		sed -i 's/#HTTP_PORT=8000/HTTP_PORT=80/g' /home/$USER/docker-jitsi-meet/.env
		sed -i 's/#ENABLE_LETSENCRYPT=1/ENABLE_LETSENCRYPT=1/g' /home/$USER/docker-jitsi-meet/.env
		sed -i 's/#LETSENCRYPT_DOMAIN=meet.example.com/LETSENCRYPT_DOMAIN=${varFQDN}/g' /home/$USER/docker-jitsi-meet/.env
		sed -i 's/#LETSENCRYPT_EMAIL=alice@atlanta.net/LETSENCRYPT_EMAIL=${varEmail}/g' /home/$USER/docker-jitsi-meet/.env
	fi
else
	echo "That is not a valid option!"
	exit

# Run docker-compose
sudo docker-compose up -d.

echo "Access the web UI at https://${varFQDN}"
