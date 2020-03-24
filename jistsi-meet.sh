#!/bin/bash

# This script will install Jitsi-Meet on your server
# It is tested with Ubuntu 18.04 LTS

# Server requirements:
# - network bandwidth
# - 1GB RAM
# - 2GHz CPU
# - 25GB Disk
# - 10GbE Net

# Operating system:
# - Ubuntu 18.04 LTS
# - root SSH or user SSH with sudo

# Firewall: 
# - port 80 TCP (HTTP)
# - port 443 TCP (HTTPS)
# - port 10000 - 20000 UDP

function header () {
  title="$*"
  text=""

  for i in $(seq ${#title} 61); do
    text+="="
  done
  text+="[ $title ]====="
  echo -e "${colorOrange}${text}${colorReset}"
}

function letsEncrypt () {
	# generating Let's Encrypt certificate
	set -e

	DEB_CONF_RESULT=`debconf-show jitsi-meet-web-config | grep jvb-hostname`
	DOMAIN="${DEB_CONF_RESULT##*:}"
	# remove whitespace
	DOMAIN="$(echo -e "${DOMAIN}" | tr -d '[:space:]')"

	echo "-------------------------------------------------------------------------"
	echo "This script will:"
	echo "- Need a working DNS record pointing to this machine(for domain ${DOMAIN})"
	echo "- Download certbot-auto from https://dl.eff.org to /usr/local/sbin"
	echo "- Install additional dependencies in order to request Let’s Encrypt certificate"
	echo "- If running with jetty serving web content, will stop Jitsi Videobridge"
	echo "- Configure and reload nginx or apache2, whichever is used"
	echo ""
	echo "You need to agree to the ACME server's Subscriber Agreement (https://letsencrypt.org/documents/LE-SA-v1.1.1-August-1-2016.pdf) "
	echo "by providing an email address for important account notifications"

	echo -n "Enter your email and press [ENTER]: "
	read EMAIL

	cd /usr/local/sbin

	if [ ! -f certbot-auto ] ; then
	  wget https://dl.eff.org/certbot-auto
	  chmod a+x ./certbot-auto
	fi

	CRON_FILE="/etc/cron.weekly/letsencrypt-renew"
	echo "#!/bin/bash" > $CRON_FILE
	echo "/usr/local/sbin/certbot-auto renew >> /var/log/le-renew.log" >> $CRON_FILE

	CERT_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
	CERT_CRT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

	if [ -f /etc/nginx/sites-enabled/$DOMAIN.conf ] ; then

	    ./certbot-auto certonly --noninteractive \
	    --webroot --webroot-path /usr/share/jitsi-meet \
	    -d $DOMAIN \
	    --agree-tos --email $EMAIL

	    echo "Configuring nginx"

	    CONF_FILE="/etc/nginx/sites-available/$DOMAIN.conf"
	    CERT_KEY_ESC=$(echo $CERT_KEY | sed 's/\./\\\./g')
	    CERT_KEY_ESC=$(echo $CERT_KEY_ESC | sed 's/\//\\\//g')
	    sed -i "s/ssl_certificate_key\ \/etc\/jitsi\/meet\/.*key/ssl_certificate_key\ $CERT_KEY_ESC/g" \
	        $CONF_FILE
	    CERT_CRT_ESC=$(echo $CERT_CRT | sed 's/\./\\\./g')
	    CERT_CRT_ESC=$(echo $CERT_CRT_ESC | sed 's/\//\\\//g')
	    sed -i "s/ssl_certificate\ \/etc\/jitsi\/meet\/.*crt/ssl_certificate\ $CERT_CRT_ESC/g" \
	        $CONF_FILE

	    echo "service nginx reload" >> $CRON_FILE
	    service nginx reload

	    TURN_CONFIG="/etc/turnserver.conf"
	    if [ -f $TURN_CONFIG ] && grep -q "jitsi-meet coturn config" "$TURN_CONFIG" ; then
	        echo "Configuring turnserver"
	        sed -i "s/cert=\/etc\/jitsi\/meet\/.*crt/cert=$CERT_CRT_ESC/g" $TURN_CONFIG
	        sed -i "s/pkey=\/etc\/jitsi\/meet\/.*key/pkey=$CERT_KEY_ESC/g" $TURN_CONFIG

	        echo "service coturn restart" >> $CRON_FILE
	        service coturn restart
	    fi
	elif [ -f /etc/apache2/sites-enabled/$DOMAIN.conf ] ; then

	    ./certbot-auto certonly --noninteractive \
	    --webroot --webroot-path /usr/share/jitsi-meet \
	    -d $DOMAIN \
	    --agree-tos --email $EMAIL

	    echo "Configuring apache2"

	    CONF_FILE="/etc/apache2/sites-available/$DOMAIN.conf"
	    CERT_KEY_ESC=$(echo $CERT_KEY | sed 's/\./\\\./g')
	    CERT_KEY_ESC=$(echo $CERT_KEY_ESC | sed 's/\//\\\//g')
	    sed -i "s/SSLCertificateKeyFile\ \/etc\/jitsi\/meet\/.*key/SSLCertificateKeyFile\ $CERT_KEY_ESC/g" \
	        $CONF_FILE
	    CERT_CRT_ESC=$(echo $CERT_CRT | sed 's/\./\\\./g')
	    CERT_CRT_ESC=$(echo $CERT_CRT_ESC | sed 's/\//\\\//g')
	    sed -i "s/SSLCertificateFile\ \/etc\/jitsi\/meet\/.*crt/SSLCertificateFile\ $CERT_CRT_ESC/g" \
	        $CONF_FILE

	    echo "service apache2 reload" >> $CRON_FILE
	    service apache2 reload
	else
	    service jitsi-videobridge stop

	    ./certbot-auto certonly --noninteractive \
	    --standalone \
	    -d $DOMAIN \
	    --agree-tos --email $EMAIL

	    echo "Configuring jetty"

	    CERT_P12="/etc/jitsi/videobridge/$DOMAIN.p12"
	    CERT_JKS="/etc/jitsi/videobridge/$DOMAIN.jks"
	    # create jks from  certs
	    openssl pkcs12 -export \
	        -in $CERT_CRT -inkey $CERT_KEY -passout pass:changeit > $CERT_P12
	    keytool -importkeystore -destkeystore $CERT_JKS \
	        -srckeystore $CERT_P12 -srcstoretype pkcs12 \
	        -noprompt -storepass changeit -srcstorepass changeit

	    service jitsi-videobridge start

	fi

	# the cron file that will renew certificates
	chmod a+x $CRON_FILE
}

# ========================================================================= #
# ==================== Running script from here =========================== #
# ========================================================================= #

# This script should be run as root
if [[ "$EUID" -ne 0 ]]
  then echo "Please run as root"
  exit
fi

# Setting the FQDN
read -p 'What will be the FQDN? ' varFQDN

# Set Firewall rules - UFW
header Setting Firewall Rules
# enabling ufw
ufw enable
# allow ssh (or else you can lock yourself out of the server)
ufw allow in ssh
# allow HTTP, HTTPS and UDP range 10000:20000
ufw allow in 80/tcp
ufw allow in 443/tcp
ufw allow in 10000:20000/udp

# Basic Jitsi Meet Install
header Installing Jitsi Meet
# adding FQDN in hosts file
echo "127.0.0.1 localhost ${varFQDN}" | tee -a /etc/hosts

# adding repository
echo 'deb https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list
wget -qO -  https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -

# update package lists
apt update

# install package foor https transport
apt install apt-transport-https

# install Jitsi Meet package
echo
echo "During the installation proces you have to typ in the hostname."
echo "You can enter here the FQDN: ${varFQDN}"
echo
echo "You also have to choose which certificate you want to use."
echo "If you don't have your own certificate, choose to generate a new self-signed certificate."
echo "You can later get a change to obtain a Let's Encrypt generated certificate."
read 'Press enter to continue...'
apt install jitsi-meet -y

# Choose if you want a Let's Encrypt certificate or own
read -p "Do you want to generate a Let's Encrypt certificate? [y/n]" varCertificate
if [[ $varCertificate =~ [yYnN] ]]; then
	if [[ $varCertificate =~ [yY] ]]; then
		header Generating Let\'s Encrypt certificate
		letsEncrypt
	fi
else
	echo "That's not a valid option!!!"
fi

echo
echo "The installation of Jitsi Meet is done."
echo "To check if all is running properly, open your browser and direct it to ${varFQDN}"
echo "You can start by creating your channel and sneding other people the link."
echo
