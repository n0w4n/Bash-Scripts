#!/bin/bash

# this script will setup a Jitsi Meet docker container

versionNumber="1.4"
colorReset='\e[0m'
colorRed='\e[31m'
colorGreen='\e[32m'
colorOrange='\e[33m'

function banner () {
	echo -e "${colorOrange}
##################################################
##                                              ##
##    Jitsi Meet Docker installation script     ##
##                                              ##
##    Created by n0w4n                          ##
##                                              ##
##################################################
   
  Version: ${versionNumber}
  ${colorReset}"
}

function installContainer () {
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
	echo -e "${colorOrange}What is the FQDN? ${colorReset}"
	read varFQDN
	echo -e "${colorOrange}What is the mailadres for corresponding? ${colorReset}" 
	read varEmail

	# Setup certificate
	echo -e "${colorOrange}Use Let's Encrypt certificate? [y/n]${colorReset}" 
	read varCert
	if [[ $varCert =~ [yYnN] ]]; then
		if [[ $varCert =~ [yY] ]]; then
			echo -e "${colorGreen}Enabling Let's Encrypt settings in .env file${colorReset}"
			sed -i 's/HTTP_PORT=8000/HTTP_PORT=80/g' /home/"${USER}"/docker-jitsi-meet/.env
			sed -i 's/HTTPS_PORT=8443/HTTPS_PORT=443/g' /home/"${USER}"/docker-jitsi-meet/.env
			sed -i "s/#PUBLIC_URL=https:\/\/meet.example.com/PUBLIC_URL=https:\/\/${varFQDN}/g" /home/"${USER}"/docker-jitsi-meet/.env
			sed -i 's/#ENABLE_LETSENCRYPT=1/ENABLE_LETSENCRYPT=1/g' /home/"${USER}"/docker-jitsi-meet/.env
			sed -i "s/#LETSENCRYPT_DOMAIN=meet.example.com/LETSENCRYPT_DOMAIN=${varFQDN}/g" /home/"${USER}"/docker-jitsi-meet/.env
			sed -i "s/#LETSENCRYPT_EMAIL=alice@atlanta.net/LETSENCRYPT_EMAIL=${varEmail}/g" /home/"${USER}"/docker-jitsi-meet/.env
			sed -i "s/#ENABLE_HTTP_REDIRECT=1/ENABLE_HTTP_REDIRECT=1/g" /home/"${USER}"/docker-jitsi-meet/.env
		fi
	else
		echo -e "${colorRed}That is not a valid option!${colorReset}"
		exit
	fi

	# Run docker-compose
	cd /home/$USER/docker-jitsi-meet
	sudo docker-compose up -d

	echo -e "${colorGreen}Access the web UI at https://${varFQDN}${colorReset}"
}

function eraseContainers () {
	# if for some reason the container is not working and you want to alter the env file
	
	# kills all containers
	sudo docker-compose kill

	# remove all containers (press Y when needed)
	sudo docker system prune -a
}

# checks if there is an argument given
if [[ $# -eq 0 ]]; then
	echo "Give argument 'install', 'erase' or help"
	exit 2
fi

if [[ ${1} == "install" ]]; then
	clear
	banner
	installContainer
	exit
elif [[ ${1} == "erase" ]]; then
	clear
	banner
	eraseContainers
	exit
elif [[ ${1} == "help" ]]; then
	clear
	banner
	helpSection
	exit
else
	echo "Valid arguments are 'install', 'erase' or 'help' only!"
	exit 2
fi
