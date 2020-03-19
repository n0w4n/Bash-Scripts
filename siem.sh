#!/bin/bash

# This script will try to do as much as the work for
# you and help install and configure an SIEM setup.
# This script was written and tested on Ubuntu Server 18.04 LTS

# Global variables
versionNumber="1.9.1"
varDomain="siem.local"
colorReset='\e[0m'
colorRed='\e[30m'
colorGreen='\e[31m'
colorOrange='\e[33m'

# Functions
function banner () {
	echo -e "${colorOrange}
#######################################################################
##                                                                   ##
##      SIEM Installation script (ElasticSearch, Kibana, Beat)       ##
##                                                                   ##
##      Created by n0w4n                                             ##
##                                                                   ##
#######################################################################
   
  Version: ${versionNumber}
  ${colorReset}"
}

function header () {
  title="$*"
  text=""

  for i in $(seq ${#title} 61); do
    text+="="
  done
  text+="[ $title ]====="
  echo -e "${colorOrange}${text}${colorReset}"
}

function preReq () {
	# checks all the prerequisites
	header Prerequisites

	# checking for the correct sudo rights
	sudo -n true &>/dev/null
	if [[ $? -eq 1 ]]; then
		echo "${USER} needs passwordless sudo access"
		echo "Use 'sudo visudo' and change the following:"
		echo "%sudo ALL=(ALL:ALL) ALL"
		echo "%sudo ALL=(ALL) NOPASSWD: ALL"
		echo "Close the texteditor with CTRL+X and confirm with y"
		echo "Exiting"
		exit 1
	fi

	# updates system
	sudo apt update 
	sudo apt upgrade -y

	# Checking for Java 8
	which java &>/dev/null
	if [[ $? -eq 1 ]]; then
		echo "Java not found!"
		installJava
	else
		echo "Java is installed"
	fi

	# Checking for Nginx
	which nginx &>/dev/null
	if [[ $? -eq 1 ]]; then
		header Nginx not found!
		installNginx
	else
		echo "Nginx is installed"
	fi
}

function installJava () {
	header installing Java 8
	# installs Java 8
	sudo apt install openjdk-8-jre-headless -y

	# Changing the env to the correct Java installation
	echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" | sudo tee -a /etc/enviroment
	source /etc/enviroment
}

function installNginx () {
	# install Nginx Server
	header Installing Nginx Server
	sudo apt install nginx -y
	
	# setting Nginx to auto-start
	sudo /bin/systemctl enable nginx

	# changing Firewall rules
	sudo ufw allow 'Nginx HTTP'

	# Setting up Server block for domain
	sudo mkdir -p /var/www/${varDomain}/html
	sudo chown -R ${USER}:${USER} /var/www/${varDomain}/html
	sudo bash -c "cat > /var/www/${varDomain}/html/index.html" << EOF
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
	sudo /bin/systemctl restart nginx
}

function installSiemApps () {
	header Installing ElasticSearch
	# importing ElasticSearch PGP key
	wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

	# installing https transport package
	sudo apt install apt-transport-https -y

	# saving repo definition to own sources.list
	echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

	# installing ElasticSearch
	sudo apt update
	sudo apt install elasticsearch -y

	# installing Kibana
	header Installing Kibana
	sudo apt install kibana -y

	# installing Logstash
	header Installing Logstash
	sudo apt install logstash -y

	# installing filebeat
	header Installing Filebeat
	curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.4.0-amd64.deb
	sudo dpkg -i filebeat-7.4.0-amd64.deb
	sudo rm filebeat*

	# setting modules filebeat
	sudo filebeat modules enable system
	sudo filebeat modules enable cisco
	sudo filebeat modules enable netflow
	sudo filebeat modules enable osquery
	sudo filebeat modules enable elasticsearch
	sudo filebeat modules enable kibana
	sudo filebeat modules enable logstash

	# installing metricbeat
	header Installing Metricbeat
	curl -L -O https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-7.4.0-amd64.deb
	sudo dpkg -i metricbeat-7.4.0-amd64.deb
	sudo rm metricbeat*

	# setting modules metricbeat
	sudo metricbeat modules enable elasticsearch
	sudo metricbeat modules enable kibana
	sudo metricbeat modules enable logstash
	sudo metricbeat modules enable system

	# installing packetbeat
	header Installing Packetbeat
	sudo apt-get install libpcap0.8
	curl -L -O https://artifacts.elastic.co/downloads/beats/packetbeat/packetbeat-7.4.0-amd64.deb
	sudo dpkg -i packetbeat-7.4.0-amd64.deb
	sudo rm packetbeat*

	# installing auditbeat
	header Installing Auditbeat
	curl -L -O https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-7.4.0-amd64.deb
	sudo dpkg -i auditbeat-7.4.0-amd64.deb
	sudo rm auditbeat*

	# reloading systemd
	header Reloading services
	sudo /bin/systemctl daemon-reload
	echo "Done"

	# starting and enabling systemd services
	header Starting services

	echo "Starting ElasticSearch"
	sudo /bin/systemctl enable elasticsearch.service
	sudo /bin/systemctl start elasticsearch.service

	echo "Starting Kibana"
	sudo /bin/systemctl enable kibana.service
	sudo /bin/systemctl start kibana.service

	echo "Starting Logstash"
	sudo /bin/systemctl enable logstash.service
	sudo /bin/systemctl start logstash.service

	echo "Starting Filebeat"
	sudo /bin/systemctl enable filebeat
	sudo /bin/systemctl start filebeat
	sudo filebeat setup -e
	sudo filebeat setup --dashboards
	sudo filebeat setup --index-management
	sudo filebeat setup --pipelines

	echo "Starting Metricbeat"
	sudo /bin/systemctl enable metricbeat
	sudo /bin/systemctl start metricbeat
	sudo metricbeat setup -e
	sudo metricbeat setup --dashboards
	sudo metricbeat setup --index-management
	sudo metricbeat setup --pipelines

	echo "Starting Packetbeat"
	sudo /bin/systemctl enable packetbeat
	sudo /bin/systemctl start packetbeat
	sudo packetbeat setup -e
	sudo packetbeat setup --dashboards
	sudo packetbeat setup --index-management
	sudo packetbeat setup --pipelines

	echo "Starting Auditbeat"
	sudo /bin/systemctl enable auditbeat
	sudo /bin/systemctl start auditbeat
	sudo auditbeat setup -e
	sudo auditbeat setup --dashboards
	sudo auditbeat setup --index-management
	sudo auditbeat setup --pipelines
}

function lastStep () {
	echo "$(tput setaf 1) ---- Now It's Your Turn: Finsh Configuration ----"
	echo "$(tput setaf 3) 1. edit kibana.yml and change server.host to 0.0.0.0 so that you can connect to kibana from other systems http://IPADDRESS:5601"
	echo "$(tput setaf 3) 2. edit elasticsearch.yml and change network.host to 0.0.0.0 so that other systems can send data to elasticsearch"
	echo "$(tput setaf 3) 3. restart both services sudo /bin/systemctl restart elasticsearch kibana"	
}

clear
banner
preReq
installSiemApps
header Done
echo "Installation of all packages are complete"
echo "Exiting"
exit
