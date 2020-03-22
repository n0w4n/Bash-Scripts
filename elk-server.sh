#!/bin/bash

# This script will try to do as much as the work for
# you and help install and configure an SIEM setup.
# This script was written and tested on Ubuntu Server 18.04 LTS

# Global variables
versionNumber="1.0"
domainName="siem.local"
ipAddress=$(hostname -I)
colorReset='\e[0m'
colorRed='\e[30m'
colorGreen='\e[31m'
colorOrange='\e[33m'

# Functions
function header () {
  title="$*"
  text=""

  for i in $(seq ${#title} 61); do
    text+="="
  done
  text+="[ $title ]====="
  echo -e "${colorOrange}${text}${colorReset}"
}

function banner () {
	echo -e "${colorOrange}
#######################################################################
##                                                                   ##
##    ELK Installation script (ElasticSearch, Kibana, FileBeat)      ##
##                                                                   ##
##    Created by n0w4n                                               ##
##                                                                   ##
#######################################################################
   
  Version: ${versionNumber}
  ${colorReset}"
}

function installJava () {
	header installing Java 8
	# installs Java 8
	sudo apt install openjdk-8-jre-headless -y

	# Changing the env to the correct Java installation
	echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" | sudo tee -a /etc/enviroment
	source /etc/enviroment
}

function installElasticSearch () {
	header Installing ElasticSearch

	# downloading Elasticsearch followed by public signing key
	sudo wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

	# installing the apt-transport-https package (Debian based distros needs this)
	sudo apt install apt-transport-https -y

	# adding the repository
	echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

	# updating the repo list and installing the package
	sudo apt update
	sudo apt install elasticsearch -y

	# uncommenting “network.host” and “http.port”
	sudo sed -i 's/#network.host: localhost/network.host: localhost/g' /etc/elasticsearch/elasticsearch.yml
	sudo sed -i 's/#http.port: 9200/#http.port: 9200/g' /etc/elasticsearch/elasticsearch.yml

	# enabling ElasticSearch on boot
	sudo systemctl enable elasticsearch.service

	# starting ElasticSearch
	sudo systemctl start elasticsearch.service
}

function installKibana () {
	# installing Kibana
	header Installing Kibana
	sudo apt install kibana -y

	# uncommenting following lines
	sudo sed -i 's/#server.port: 5601/server.port: 5601/g' /etc/kibana/kibana.yml
	sudo sed -i 's/#server.host: \"localhost\"/server.host: \"localhost\"/g' /etc/kibana/kibana.yml
	sudo sed -i 's/#elasticsearch.url: \"http:\/\/localhost:9200\"/elasticsearch.url: "http:\/\/localhost:9200\"/g' /etc/kibana/kibana.yml

	# enabling Kibana on boot
	sudo systemctl enable kibana.service

	# starting Kibana
	sudo systemctl start kibana.service
}

function installNginx () {
	# installing Nginx
	header Installing nginx apache2-utils -y

	# configuring virtual host
	sudo bash -c "cat > /etc/nginx/sites-available/elk" << EOF
server {
    listen 80;
 
    server_name ${domainName};
 
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.elkusersecret;
 
    location / {
        proxy_pass http://localhost:5601;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

	# creating user + passwd file for web browser authentication
	sudo htpasswd -c /etc/nginx/.elkusersecret elkusr

	# enabling Nginx on boot
	sudo systemctl enable nginx.service

	# starting Nginx
	sudo systemctl restart nginx.service
}

function installLogstash () {
	# installing Logstash
	sudo apt install logstash -y

	# modifying host file
	echo "${ipAddress} elk-server elk-server" | sudo tee -a /etc/hosts

	# create folder for SSL certificate
	sudo mkdir -p /etc/logstash/ssl

	# generating SSL certificate
	sudo openssl req -subj '/CN=elk-server/' -x509 -days 3650 -batch -nodes -newkey rsa:2048 -keyout /etc/logstash/ssl/logstash-forwarder.key -out /etc/logstash/ssl/logstash-forwarder.crt

	# creating filebeat-input file
	sudo bash -c "cat > /etc/logstash/conf.d/filebeat-input.conf" << EOF
input {
  beats {
    port => 5443
    type => syslog
    ssl => true
    ssl_certificate => "/etc/logstash/ssl/logstash-forwarder.crt"
    ssl_key => "/etc/logstash/ssl/logstash-forwarder.key"
  }
}
EOF
	
	# creating new configuration file
	sudo bash -c "cat > /etc/logstash/conf.d/syslog-filter.conf" << EOF
filter {
  if [type] == "syslog" {
    grok {
      match => { "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_hostname} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}" }
      add_field => [ "received_at", "%{@timestamp}" ]
      add_field => [ "received_from", "%{host}" ]
    }
    date {
      match => [ "syslog_timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
    }
  }
}
EOF
	
	# create elasticSearch output file
	sudo bash -c "cat > /etc/logstash/conf.d/syslog-filter.conf" << EOF
output {
  elasticsearch { hosts => ["localhost:9200"]
    hosts => "localhost:9200"
    manage_template => false
    index => "%{[@metadata][beat]}-%{+YYYY.MM.dd}"
    document_type => "%{[@metadata][type]}"
  }
}
EOF

	# enabling Logstash on boot
	sudo systemctl enable logstash.service

	# starting Logstash
	sudo systemctl start logstash.service
}

function installFileBeat () {
	# this function should be run on client-servers
	# adding host to hosts file
	echo "${ipAddress} elk-server" | sudo tee -a /etc/hosts

	# downloading and installing public signing key
	sudo wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

	# installing “apt-transport-https” and add repo
	sudo apt install apt-transport-https -y
	sudo echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

	# updating repo
	sudo apt update

	# installing filebeat
	sudo apt install filebeat -y

	# modifying filebeat configurations
	sudo sed -i 's/enabled: false/enabled: true/g' /etc/filebeat/filebeat.yml

	sudo sed -i 's/#output.logstash:/output.logstash:/g' /etc/filebeat/filebeat.yml
	sudo sed -i 's/#  hosts: ["elk-server:5443"]/  hosts: ["elk-server:5443"]/g' /etc/filebeat/filebeat.yml
	sudo sed -i 's/#  ssl.certificate_authorities: ["/etc/filebeat/logstash-forwarder.crt"]/  ssl.certificate_authorities: ["/etc/filebeat/logstash-forwarder.crt"]/g' /etc/filebeat/filebeat.yml

	sudo sed -i 's/output.elasticsearch:/#output.elasticsearch:/g' /etc/filebeat/filebeat.yml
	sudo sed -i 's/   hosts: ["localhost:9200"]/  # hosts: ["localhost:9200"]/g' /etc/filebeat/filebeat.yml

	echo
	echo "To finish installation follow these steps:"
	echo "1. Log in on the ELK server and typ in the following command:"
	echo "   sudo cat /etc/logstash/ssl/logstash-forwarder.crt"
	echo "2. Copy the output from that command."
	echo "3. Log in on the ELK client-server and create a certificate file with the following command:"
	echo "   sudo vim /etc/filebeat/logstash-forwarder.crt"
	echo "4. Insert (paste) copied output and save & exit file."
	echo 
	read -p 'When you have completed the steps above, press enter to continue...'

	# enabling filebeat on boot
	sudo systemctl enable filebeat.service

	# starting filebeat
	sudo systemctl start filebeat.service
}

function commentsClient () {
	echo "You've have installed ELK"
	echo "To browse Kibana open up your favorite browser and typ in:"
	echo "http://${domainName} followed by username and password"
	echo
	echo "Enter the created user name and password. You should see the Kibana Welcome page. Click “Explore my Own” button."
	echo "You should be directed to the Kibana Home Page."
	echo "Click “Discover” on the left side. Click “Create index pattern”."
	echo "Then define the index pattern  “filebeat-*”."
	echo "Click next and choose @timestamp’ and click ‘Create index pattern’."
	echo "Index pattern should get created."
	echo "Click the “Discover” Menu to see the server logs."
	echo "Logs will be shown as per the time stamp. Click on any timestamp to expand it and see the log file contents and its details."
	echo
}

function commentServer () {
	echo "You have finished installing ELK on this server."
	echo "Now you can run this script on the client-server."
	echo "To check if everything is running properly, you can run this script in debug mode."
	echo
}

function debugInstall () {
	# debug Java
	header Checking Java
	java -version
	echo "${JAVA_HOME}"
	read -p 'Press enter to continue...'

	# debug ElasticSearch
	header Checking ElasticSearch
	sudo curl -XGET 'localhost:9200/?pretty'
	read -p 'Press enter to continue...'

	# debug Nginx
	header Checking Nginx
	sudo nginx -t
	read -p 'Press enter to continue...'
}

# checks if there is an argument given
if [[ $# -eq 0 ]]; then
	echo "Give argument 'windows' or 'linux'"
	exit 2
fi

if [[ ${1} == "server" ]]; then
	clear
	banner
	header Updating repository
	sudo apt update
	installJava
	installElasticSearch
	installKibana
	installNginx
	installLogstash
	commentServer
	exit
elif [[ ${1} == "client" ]]; then
	clear
	banner
	header Updating repository
	sudo apt update
	installFileBeat
	commentsClient
	exit
elif [[ ${1} == "debug" ]]; then
else
	echo "Valid arguments are 'server', 'client' or 'debug' only!"
	exit 2
fi
