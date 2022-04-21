#!/bin/bash

# How to use:
# $ local_site.sh add mysite.local
	# This option allows swiftly setting up a virtual directory on Apache
	# It creates an SSL certificate (and puts it in the right place)
	# Creates the directory, gives permission for you to work there. 
	# It then adds the directory as Virtual Directory in Apache and configures it to serve via https
# or
# $ local_site.sh del mysite.local
	# This option allows swiftly deleting a virtual directory on Apache added by the "add" option of this script
	# It deletes the SSL certificate
	# Delete the directory
	# Removes the directory as Virtual Directory in Apache


# IMPORTANT 1 - Install mkcert before using this script. 
# mkcert is a simple tool for making locally-trusted development certificates. It requires no configuration.
# Instructions:
# 1 - go to https://github.com/FiloSottile/mkcert/releases and download to the same directory as this script
# 2 - $ sudo chmod +x mkcert-v1.4.3-linux-amd64
# To make Chrome and Firefox not complain about these self-signed certificate
# 3 - $ apt install libnss3-tools
# 4 - $ mkcert-v1.4.3-linux-amd64 -install

# IMPORTANT 2 - The file 000-local-ssl.conf needs to be on the same directory as this script

# IMPORTANT 3 - This script needs to be executable
# $ chmod +x local_site.sh


# print the commands
#set -o xtrace

SCRIPTNAME=$(basename $BASH_SOURCE)

if [ $1 = "add" ]
then

	# Get script location
	BASEDIR=$(dirname $0)

	cd /home/$USER

	# Create the local certificate
	mkcert-v1.4.3-linux-amd64 $2 >/dev/null 2>&1

	# changed owner to root
	sudo chown root:root $2.pem
	sudo chown root:root $2-key.pem

	# move the certificates (public and private to their directories)
	sudo mv $2.pem /etc/ssl/certs/
	sudo mv $2-key.pem /etc/ssl/private/

	# create the web directory 
	sudo rm -rf /var/www/$2
	sudo mkdir /var/www/$2

	# give apache user the right permissions for the web directory
	sudo chown -R $USER:www-data /var/www/$2
	#sudo chmod -R 770 /var/www/$2

	# copy the template .config file  
	sudo cp $BASEDIR/000-local-ssl.conf /etc/apache2/sites-available/$2.conf

	# replace the palceholder text with the correct domain
	sudo sed -i "s/__local_domain__/$2/g" /etc/apache2/sites-available/$2.conf

	# add domain to hosts file
	#echo "127.0.0.1 $2" | sudo tee -a /etc/hosts 
	#sudo bash -c "echo \"127.0.0.1 $2\" >> /etc/hosts"
	sudo sed -i "1i127.0.0.1 $2" /etc/hosts

	# make the site available
	sudo a2ensite $2.conf >/dev/null 2>&1

	# reload the server
	sudo systemctl reload apache2

	bold=$(tput bold)
	normal=$(tput sgr0)
	echo "${bold}$2${normal} added"
	echo "You can work on /var/www/$2"
	
elif [ $1 = "del" ] 
then

	# remove the site form sites-enabled
	sudo a2dissite $2.conf >/dev/null 2>&1

	# delete the .config file from sites-available  
	sudo rm /etc/apache2/sites-available/$2.conf

	# delete the certificates (public and private from their directories)
	sudo rm /etc/ssl/certs/$2.pem 
	sudo rm /etc/ssl/private/$2-key.pem 

	# delete the web directory 
	sudo rm -rf /var/www/$2

	# remove domain from hosts file
	sudo sed -i "s/127.0.0.1 $2//" /etc/hosts

	# reload the server
	sudo systemctl reload apache2

	bold=$(tput bold)
	normal=$(tput sgr0)
	echo "${bold}$2${normal} deleted"

else
	echo "Incorrect use of script."
	echo "Usage:"
	echo "$SCRIPTNAME add siteName"
	echo "or"
	echo "$SCRIPTNAME del siteName"
fi
