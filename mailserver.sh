#!/bin/bash

# This script is to setup a mailserver for webmail
# It will install Postfix, Dovecot and RainLoop
# It is recommended to use this setup in a LAB enviroment only as it is NOT secure
# It is created to set up a quick mailserver for an attacker to send a victim a mail
# For training purposes only (phishing, network analyses, etc.)
# Use it at your own risk.

# Functions
function banner () {
	echo
	echo "####################################################"
	echo "##                                                ##"
	echo "##      Automated install of mail server          ##"
	echo "##      created by n0w4n                          ##"
	echo "##                                                ##"
	echo "####################################################"
	echo
}

function header () {
	title="$*"
	text=""

	for i in $(seq ${#title} 70); do
	text+="="
	done
	text+="[ ${title} ]====="
	echo -e "\e[33m${text}\e[0m"
}

function Step1 () {
	# Step 1: Initial Configurations for Postfix Mail Server on Debian
	# Updating system
	header upgrading system
	sudo apt update
	sudo apt upgrade -y

	# Install the following software packages that will be used for system administration
	header installing system administration tools
	sudo apt install curl net-tools bash-completion wget lsof nano -y

	# Change value of file for DNS resolution purposes
	header altering /etc/hosts.conf file
	sudo  cat <<EOF > /etc/host.conf
order hosts,bind
multi on
EOF

	# Setup machine FQDN and add domain name and system FQDN
	header setting hostname
	read -p '[!] What is the required domain? (example: domain.com): ' nameDomain
	read -p '[!] What is the required FQDN? (example: mail.domain.com): ' nameHost
	read -p '[!] What is the static IP address of the server?: ' ipServer
	sudo hostnamectl set-hostname "${nameHost}"
	echo "${ipServer} ${nameDomain} ${nameHost}" | sudo tee -a /etc/hosts &>/dev/null

	# Restart machine to activate changes
	header restarting machine
	echo "After reboot please run this script again to continue."
	read -p 'Press enter to continue...'

	# Section to maintain information about prior installation steps
	# Creates marker file to make sure the script skips Step 1
	touch ~/marker1
	# Store temp variables in .bashrc for save keeping during reboot
	echo "export nameDomain=${nameDomain}" | tee -a ~/.bashrc &>/dev/null
	echo "export nameHost=${nameHost}" | tee -a ~/.bashrc &>/dev/null
	echo "export ipServer=${ipServer}" | tee -a ~/.bashrc &>/dev/null

	# Reboot
	sudo init 6
}

function Step2 () {
	# Installing Postfix Mail Server
	header installing Postfix mail server
	echo "[!] In Postfix configuration, choose for option: 'Internet Site'"
	read -p 'Press enter to continue...'
	sudo apt install postfix -y

	# Create backup of postfix config file
	header creating backup of postfix config file
	sudo cp /etc/postfix/main.cf{,.backup}

	# Altering postfix config file
	header altering postfix config file
		# To store the correct variables this file will be temp stored in local folder
	sudo cat <<EOF > /etc/postfix/main.cf
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

smtpd_banner = $myhostname ESMTP
biff = no
# appending .domain is the MUA's job.
append_dot_mydomain = no
readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = ${nameHost}

mydomain = ${nameDomain}

alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

#myorigin = /etc/mailname
myorigin = ${nameDomain}

mydestination = ${nameHost}, ${nameDomain}, localhost.${nameDomain}, localhost
relayhost = 
mynetworks = 127.0.0.0/8, ${ipServer}/24
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
#inet_protocols = all
inet_protocols = ipv4

home_mailbox = Maildir/

# SMTP-Auth settings
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = ${nameHost}
smtpd_recipient_restrictions = permit_mynetworks,permit_auth_destination,permit_sasl_authenticated,reject
EOF

	# Dump Postfix main configuration file
	header loading new config file
	sudo postconf -n

	# Restart Postfix
	header restarting Postfix
	sudo systemctl enable postfix
	sudo systemctl restart postfix
}

function Step3 () {
	# Installing mailutils
	header Installing mailutils
	sudo apt install mailutils -y
}

function Step4 () {
	# Installing Dovecot MTA
	header installing Dovecot
	sudo apt install dovecot-core dovecot-imapd -y

	# Changing Dovecot config files
	header changing Dovecot config file
	sudo sed -i 's/#listen = *, ::/listen = *, ::/g' /etc/dovecot/dovecot.conf
	header changing Dovecot auth file
	sudo sed -i 's/#disable_plaintext_auth = yes/disable_plaintext_auth = no/g' /etc/dovecot/conf.d/10-mail.conf
	sudo sed -i 's/auth_mechanisms = plain/auth_mechanisms = plain login/g' /etc/dovecot/conf.d/10-auth.conf
	sudo sed -i 's/mail_location = mbox/#mail_location = mbox/g' /etc/dovecot/conf.d/10-auth.conf
	echo "mail_location = maildir:~/Maildir" | sudo tee -a /etc/dovecot/conf.d/10-mail.conf &>/dev/null
	sudo sed -i 's/# Postfix smtp-auth/# Postfix smtp-auth\n  unix_listener \/var\/spool\/postfix\/private\/auth {\n  mode = 0666\n  user = postfix\n  group = postfix\n}\n\n  # Postfix smtp-auth/g' /etc/dovecot/conf.d/10-master.conf

	# Restarting Dovecot
	header restarting Dovecot
	sudo systemctl enable dovecot
	sudo systemctl restart dovecot
}

function Step5 () {
	# Create new user
	header creating new user
	read -p 'What is the name of the new user? ' newUser
	useradd -s /bin/bash -m "${newUser}"
	usermod -aG sudo "${newUser}"
	passwd "${newUser}"
}

function Step6 () {
	# Install and configure webmail
	versionPHP=`php -v | head -n1 | awk '{print $2}' | cut -d. -f2`
	if [[ ${versionPHP} -eq 0 ]]; then
		header installing php dependencies
		sudo apt install apache2 php7.4 libapache2-mod-php7.4 php7.4-curl php7.4-xml -y
	else
		header installing php dependencies
		sudo apt install apache2 php7."${versionPHP}" libapache2-mod-php7."${versionPHP}" php7."${versionPHP}"-curl php7."${versionPHP}"-xml -y
	fi

	# Enabling & starting Apache2 httpd
	header enabling Apache2 httpd
	sudo systemctl enable apache2
	sudo systemctl start apache2

	# Install Rainloop webmail client
	header installing Rainloop webmail client
	cd /var/www/html/
	rm index.html 
	curl -sL https://repository.rainloop.net/installer.php | php

	echo "[!] Navigate with the browser to ${ipServer}/?admin"
	echo "[!] User = admin"
	echo "[!] Password = 12345"
	echo "[!] Navigate to Domains menu, hit on Add Domain button and add your domain name settings"
	echo "[!] IMAP server = 127.0.0.1"
	echo "[!] SMTP server = 127.0.0.1"
	echo "[!] Option 'use short login' should be checked"
	echo "[!] Regular user can log in with username@domain"
}

if [[ ! -f ~/marker1 ]]; then
	clear
	banner
	Step1
else
	clear
	banner
	Step2
	Step3
	Step4
	Step5
	Step6
fi

header installation sequence is done.
# Removing temp stuff only placed for check
# Removes marker
rm ~/marker1
# Removes added variables from .bashrc file
for i in {1..3}; do sed -i '$d' ~/.bashrc; done

# Exiting script
echo "[!] Exiting program."
exit 0
