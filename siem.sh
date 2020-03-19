#!/bin/bash

# This script will try to do as much as the work for
# you and help install and configure an SIEM setup.
# This script was written and tested on Ubuntu Server 18.04 LTS

# Global variables
versionNumber="1.7"
varDomain="siem.local"
colorReset='\e[0m'
colorRed='\e[30m'
colorOrange='\e[33m'

# Functions
function banner () {
	echo -e "${colorOrange}
###########################################################################
##                                                                       ##
##          SIEM Installation script (ELK, Kibana, Beat)                 ##
##                                                                       ##
##                                                                       ##
##          Created by n0w4n                                             ##
##                                                                       ##
###########################################################################
   
  Version: ${versionNumber}
  ${colorReset}"
}

function header () {
  title="$*"
  text=""

  for i in $(seq ${#title} 60); do
    text+="="
  done
  text+="[ $title ]====="
  echo -e "${colorOrange}${text}${colorReset}"
}

function redHeader () {
  title="$*"
  text=""

  for i in $(seq ${#title} 60); do
    text+="="
  done
  text+="[ $title ]====="
  echo -e "${colorRed}${text}${colorReset}"
}

function preReq () {
	# checking for the correct sudo rights
	sudo -n true &>/dev/null
	if [[ $? -eq 1 ]]; then
		header ${USER} has no passwordless sudo access
		echo "If you want to change this, use 'sudo visudo' and change the following:"
		echo "Change: %sudo ALL=(ALL:ALL) ALL"
		echo "To    : %sudo ALL=(ALL) NOPASSWD: ALL"
		echo "Close the texteditor with CTRL+X and confirm with y"
		redHeader Exiting
		exit 1
	fi

	# updates system
	header Updating system
	sudo apt update &>/dev/null 
	sudo apt upgrade -y &>/dev/null

	# checks all the prerequisites
	# Checking for Java 8
	which java
	if [[ $? -eq 1 ]]; then
		header Java not found!
		installJava
	else
		header Java was found
	fi

	# Checking for Nginx
	which nginx
	if [[ $? -eq 1 ]]; then
		header Nginx not found!
		installNginx
	else
		header Nginx was found
	fi
}

function installJava () {
	header installing Java 8
	# installs Java 8
	sudo apt update &>/dev/null
	sudo apt install openjdk-8-jre-headless -y &>/dev/null

	# Changing the env to the correct Java installation
	echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" &>/dev/null | sudo tee -a /etc/enviroment &>/dev/null
	source /etc/enviroment
}

function installNginx () {
	# install Nginx Server
	header Installing Nginx Server
	sudo apt install nginx -y &>/dev/null
	
	# setting Nginx to auto-start
	sudo systemctl enable nginx

	# changing Firewall rules
	header Changing Firewall rules
	sudo ufw allow 'Nginx HTTP'

	# Setting up Server block for domain
	header Setting up Server Block
	sudo mkdir -p /var/www/${varDomain}/html
	sudo chown -R ${USER}:${USER} /var/www/${varDomain}/html
	sudo bash -c "cat > /var/www/${varDomain}/html" << EOF
<html>
    <head>
        <title>Welcome to ${varDomain}!</title>
    </head>
    <body>
        <h1>Success!  The ${varDomain} server block is working!</h1>
    </body>
</html>
EOF

	sudo bash -c "cat > /etc/nginx/sites-available/${varDomain}" << EOF
server {
        listen 80;
        listen [::]:80;

        root /var/www/${varDomain}/html;
        index index.html index.htm index.nginx-debian.html;

        server_name ${varDomain} www.${varDomain};

        location / {
                try_files $uri $uri/ =404;
        }
}
EOF

	sudo ln -s /etc/nginx/sites-available/"${varDomain}" /etc/nginx/sites-enabled/
	sudo sed -i 's/#server_names_hash_bucket_size/server_names_hash_bucket_size/g' /etc/nginx/nginx.conf
	sudo systemctl restart nginx
}

function installELK () {
	# importing ElasticSearch PGP key
	wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

	# installing https transport package
	sudo apt install apt-transport-https -y &>/dev/null

	# saving repo definition to own sources.list
	echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

	# installing ElasticSearch
	sudo apt update &>/dev/null
	sudo apt install elasticsearch -y &>/dev/null

	# enabling ElasticSearch to auto-start
	sudo systemctl enable elasticsearch.service

	# starting ElasticSearch 
	sudo systemctl start elasticsearch.service	
}

clear
banner
preReq
installELK
