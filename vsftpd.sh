#!/bin/bash

# script to install and configure an vsFTPd server.
# because this script will need to install programs
# and configure certain files it need to run as root

# -------- Variables ---------

ftpVar=$(dpkg -l | grep ftp)
ufwVar=$(dpkg -l | grep ufw)

# -------- Dependency --------

# check if script runs as root
if [[ ! $UID -eq 0 ]]
then
	echo "This script need to run as root!"
	exit 1
fi

# check if there is an FTP server installed
if [[ -z $ftpVar ]]
then
	echo "FTP server is not installed....installing!"
	sudo apt update && sudo apt install vsftpd -y
fi

# check if UFW firewall is installed
if [[ -z $ufwVar ]]
then
	echo "UFW is not installed....installing!"
	sudo apt update && sudo apt install ufw -y
fi

# -------- Configuration ------

# enabling UFW firewall
sudo ufw enable

# allowing ports for FTP
sudo ufw allow 20/tcp
sudo ufw allow 21/tcp
sudo ufw allow 990/tcp
sudo ufw allow 40000:50000/tcp

# ask if new FTP user is needed or use current user
read -p "Create new user as dedicated FTP user? [YES/no] " varNewUser
if [[ -z $varNewUser ]] || [[ $varNewUser =~ [Yy] ]]
then
	read -p "Name of the FTP user? " varNameUser
	if [[ -z $varNameUser ]]
	then
		echo "No name was given!"
		exit 1
	else
		sudo useradd -m -s /bin/bash $varNameUser
		sudo passwd $varNameUser
	fi
else
	read -p "Which existing user as dedicated FTP user? [name user] " varNameUser
fi

# setup chroot folder
# creating new ftp folder
sudo mkdir /home/$varNameUser/ftp
# set ownership new ftp folder
sudo chown nobody:nogroup /home/$varNameUser/ftp
# remove write permissions new ftp folder
sudo chmod a-w /home/$varNameUser/ftp
# create the directory for file uploads
sudo mkdir /home/$varNameUser/ftp/files
# assign ownership to the user
sudo chown $varNameUser:$varNameUser /home/$varNameUser/ftp/files

# altering configuration file /etc/vsftpd.conf to set security for FTP access
sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g' /etc/vsftpd.conf
sed -i 's/local_enable=NO/local_enable=YES/g' /etc/vsftpd.conf
sed -i 's/write_enable=NO/write_enable=YES/g' /etc/vsftpd.conf
sed -i 's/#write_enable=YES/write_enable=YES/g' /etc/vsftpd.conf
sed -i 's/chroot_local_user=NO/chroot_local_user=YES/g' /etc/vsftpd.conf
sed -i 's/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf

# adding lines to configuration file /etc/vsftpd.conf
echo "user_sub_token=$varNameUser" >> /etc/vsftpd.conf
echo "local_root=/home/$varNameUser/ftp" >> /etc/vsftpd.conf
echo "pasv_min_port=40000" >> /etc/vsftpd.conf
echo "pasv_max_port=50000" >> /etc/vsftpd.conf
echo "userlist_enable=YES" >> /etc/vsftpd.conf
echo "userlist_file=/etc/vsftpd.userlist" >> /etc/vsftpd.conf
echo "userlist_deny=NO" >> /etc/vsftpd.conf

# adding user to ftp userlist
echo "$varNameUser" >> /etc/vsftpd.userlist

# restart ftp server
sudo systemctl restart vsftpd

echo "Done..."
