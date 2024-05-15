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

# IMPORTANT 1 - This script needs to be executable
# $ chmod +x local_site.sh

# IMPORTANT 2 - Install mkcert before using this script.
# mkcert is a simple tool for making locally-trusted development certificates. It requires no configuration.
# https://github.com/FiloSottile/mkcert

# IMPORTANT 3 - The file 000-local-ssl.conf needs to be on the same directory as this script

# IMPORTANT 4 - To install Wordpress we need to install wp-cli first
#     https://make.wordpress.org/cli/handbook/guides/installing/

# print the commands
#set -o xtrace

SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")

mkcert_download_url="https://dl.filippo.io/mkcert/latest?for=linux/amd64"

wp_add="wp_add"
add="add"
wp_del="wp_del"
del="del"

local_domain=$2
if [ "$1" = $wp_add ] || [ "$1" = $wp_del ]; then
	local_domain=${2}.local
	# replace "-" with "_" for database and username
	db_slug=${2//[^a-zA-Z0-9]/_}

	db_name=${db_slug}_db
	db_user=${db_slug}_usr
fi

site_path=/var/www/$local_domain

if [ "$1" = "$add" ] || [ "$1" = "$wp_add" ]; then

	# Get script location
	BASEDIR=$(dirname "$0")

	if [ "$1" = "$wp_add" ]; then
		title=$2

		admin_user="admin"
		admin_email="admin@$local_domain"

		admin_user="luis"
		admin_email="luis.ferreira@gmail.com"

		echo -e '\n== Wordpress Admin User =='
		echo " - user id: $admin_user"
		echo " - email: $admin_email"
		echo "Choose password (database user will use the same):"
		echo "Note: \"Enter\" generates a random password"
		read -r -s db_pass

		if [ "${db_pass}" = "" ]; then
			echo -n "-> Generating random password... "
			db_pass="$(openssl rand -base64 12)"
			echo "done."
		fi
		admin_pass=$db_pass
	fi

	echo -e "\n== SSL + Apache =="

	#	cd /home/$USER
	cd "${BASEDIR}" || exit

	# Create the local certificate
	echo "-> Generating SSL certificate (and set it up) ... "
	if ! [ -f "mkcert" ]; then
		echo "Setting up mkcert:"
		# To make Chrome and Firefox not complain about these self-signed certificate
		echo "Install dependencies (libnss3-tools):"
		sudo apt install libnss3-tools

		echo "Downloading mkcert (and set it up)..."
		wget --quiet --show-progress -O mkcert "${mkcert_download_url}"
		sudo chmod +x mkcert
		mkcert -install
		echo "mkcert Installed."
	fi
	#mkcert-v1.4.4-linux-amd64 $local_domain >/dev/null 2>&1

	mkcert "$local_domain"

	# changed owner to root
	sudo chown root:root "$local_domain".pem
	sudo chown root:root "$local_domain"-key.pem

	# move the certificates (public and private to their directories)
	sudo mv "$local_domain".pem /etc/ssl/certs/
	sudo mv "$local_domain"-key.pem /etc/ssl/private/
	echo "done."

	echo -n "  Creating the web directory (and set it up) ... "
	sudo rm -rf "$site_path"
	sudo mkdir "$site_path"

	# give apache user the right permissions for the web directory
	sudo chown -R "$USER":www-data "$site_path"
	#sudo chmod -R 770 $site_path

	# copy the template .config file
	sudo cp "$BASEDIR"/000-local-ssl.conf /etc/apache2/sites-available/"$local_domain".conf

	# replace the palceholder text with the correct domain
	sudo sed -i "s/__local_domain__/$local_domain/g" /etc/apache2/sites-available/"$local_domain".conf

	# add domain to hosts file
	#echo "127.0.0.1 $2" | sudo tee -a /etc/hosts
	#sudo bash -c "echo \"127.0.0.1 $2\" >> /etc/hosts"
	sudo sed -i "1i127.0.0.1 $local_domain" /etc/hosts

	# make the site available
	sudo a2ensite "$local_domain".conf >/dev/null 2>&1
	echo "done."

	echo -n "  Restarting the Apache server... "
	sudo systemctl reload apache2
	echo "done."

	bold=$(tput bold)
	normal=$(tput sgr0)
	echo "${bold}$local_domain${normal} added at $site_path"

	if [ "$1" = $wp_add ]; then
		echo -e "\n== Creating Wordpress MySQL database =="
		# create mysql database
		sql=(
			"DROP DATABASE IF EXISTS $db_name;"
			"DROP USER IF EXISTS '$db_user'@'localhost';"
			"CREATE DATABASE $db_name /*\!40100 DEFAULT CHARACTER SET utf8mb4_general_ci */;"
			"CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
			"GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
			"FLUSH PRIVILEGES;"
		)

		echo "  MySQL root password:"
		read -r -s rootpasswd
		for line in "${sql[@]}"; do
			#echo "$line"
			mysql -uroot -p"${rootpasswd}" -e "$line"
		done
		echo "  Wordpress database created!"

		echo -e "\n== Setup Wordpress =="

		cd "$site_path" || exit
		wp core download

		echo "  Generating wp-config.php... "
		wp core config --dbname="$db_name" --dbuser="$db_user" --dbpass="$db_pass" --dbhost=localhost

		echo "  Installing Wordpress..."
		wp core install --url=https://"$local_domain" --title="$title" --admin_user="$admin_user" --admin_password="$admin_pass" --admin_email="$admin_email" --skip-email
	fi

elif [ "$1" = $del ] || [ "$1" = $wp_del ]; then

	echo -e "\n== SSL + Apache =="

	echo -n "  Remove Virtual Directory... "
	# remove the site form sites-enabled
	sudo a2dissite "$local_domain".conf >/dev/null 2>&1

	# delete the .config file from sites-available
	sudo rm /etc/apache2/sites-available/"$local_domain".conf
	echo "done."

	echo -n "  Deleting SSL certificate... "
	# delete the certificates (public and private from their directories)
	sudo rm /etc/ssl/certs/"$local_domain".pem
	sudo rm /etc/ssl/private/"$local_domain"-key.pem

	# delete the web directory
	sudo rm -rf "$site_path"

	# remove domain from hosts file
	sudo sed -i "s/127.0.0.1 $local_domain//" /etc/hosts
	echo "done."

	# reload the server
	echo -n "  Restarting the Apache server... "
	sudo systemctl reload apache2
	echo "done."

	bold=$(tput bold)
	normal=$(tput sgr0)

	echo "${bold}$local_domain${normal} deleted"

	if [ "$1" = $wp_del ]; then
		echo -e "\n== Deleting Wordpress MySQL database (and user) =="

		# drop mysql database
		sql=(
			"DROP DATABASE IF EXISTS $db_name;"
			"DROP USER IF EXISTS '$db_user'@'localhost';"
		)

		echo "  MySQL root password:"
		read -r -s rootpasswd
		for line in "${sql[@]}"; do
			mysql -uroot -p"${rootpasswd}" -e "$line"
		done
		echo "  Wordpress database deleted."

	fi

else
	echo "Incorrect use of script."
	echo "Usage:"
	echo "$SCRIPTNAME $add siteName"
	echo "or"
	echo "$SCRIPTNAME $wp_add siteName"
	echo "or"
	echo "$SCRIPTNAME $del siteName"
	echo "or"
	echo "$SCRIPTNAME $wp_del siteName"
fi
