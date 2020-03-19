#!/bin/bash

# This script will try to do as much as the work for
# you and help install and configure an SIEM setup.
# This script was written and tested on Ubuntu Server 18.04 LTS

# Global variables
versionNumber="1.0"
varDomain="siem.mindef.nl"

# Functions
function banner () {
	echo "   ########################################"
	echo "   ##                                    ##"
	echo "   ##      SIEM Installation script      ##"
	echo "   ##      ELK, Kibana, Beat             ##"
	echo "   ##                                    ##"
	echo "   ##      Created by n0w4n              ##"
	echo "   ##                                    ##"
	echo "   ########################################"
    echo
    echo "   Version: ${versionNumber}"
    echo
}

function header () {
  title="$*"
  text=""

  for i in $(seq ${#title} 70); do
    text+="="
  done
  text+="[ $title ]====="
  echo "$text"
}

function preReq () {\
	# updates system
	header Updating system
	sudo apt update
	sudo apt upgrade -y

	# checks all the prerequisites
	# Checking for Java 8
	#which java*
	if [[ $? -eq 1 ]]; then
		header Java 8 not found...installing Java 8
		installJava
	else
		header Java 8 was found
	fi

	# Checking for Nginx
	which nginx
	if [[ $? -eq 1 ]]; then
		header Nginx not found...installing Nginx
		installNginx
	else
		header Nginx was found
	fi
}

function installJava () {
	# installs Java 8
	sudo add-apt-repository ppa:webupd8team/java
	sudo apt update
	sudo apt install oracle-java8-installer -y

	# If system has multiple Java installations 
	# Change it to use 8 as default
	header changing default settings Java
	echo "Change the default settings to /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
	read -p 'Press enter to continue... '
	sudo update-alternatives --config java

	# Changing the env to the correct Java installation
	echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" &>/dev/null | sudo tee -a /etc/enviroment
	sudo source /etc/enviroment
}

function installNginx () {
	# install Nginx Server
	header Installing Nginx Server
	sudo apt install nginx -y
	
	# setting Nginx to auto-start
	sudo systemctl enable nginx

	# changing Firewall rules
	header Changing Firewall rules
	sudo ufw allow 'Nginx HTTP'

	# Setting up Server block for domain
	header Setting up Server Block
	sudo mkdir -p /var/www/${varDomain}/html
	sudo chown -R ${USER}:${USER} /var/www/${varDomain}/html
	cat << EOF > /var/www/${varDomain}/html
<html>
    <head>
        <title>Welcome to ${varDomain}!</title>
    </head>
    <body>
        <h1>Success!  The ${varDomain} server block is working!</h1>
    </body>
</html>
EOF

	cat << EOF > /etc/nginx/sites-available/${varDomain}
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

	sudo ln -s /etc/nginx/sites-available/${varDomain} /etc/nginx/sites-enabled/
	sudo sed -i 's/#server_names_hash_bucket_size/server_names_hash_bucket_size/g' /etc/nginx/nginx.conf
	sudo systemctl restart nginx
}

function installELK () {
	# importing ElasticSearch PGP key
	wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

	# installing https transport package
	sudo apt install apt-transport-https -y

	# saving repo definition to own sources.list
	echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

	# installing ElasticSearch
	sudo apt update && sudo apt install elasticsearch -y

	# enabling ElasticSearch to auto-start
	sudo systemctl enable elasticsearch.service
}

clear
banner
preReq
installELK
