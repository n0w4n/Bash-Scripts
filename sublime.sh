#!/bin/bash
# this script will install sublime text editor

# install sublime gpg key
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
# add source to apt repository
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
# update repository
sudo apt update
# install sublime text editor
sudo apt install sublime-text -y
