#!/bin/bash
# SWC Dev VM Initial Configuration Script
# Installs necessary software and configures the VM to run a local instance of SWC
# Note: you will need the following:
#	staging_prod.sql
# in order to complete this installation. It is not available in the repository currently

REAL_USER=$USER
BLUE="\e[34m"
RED="\e[31m"
GREEN="\e[32m"
NONE="\e[0m"

function do_install {
	echo -n -e "Installing ${BLUE}$2${NONE}..."
	sudo apt-get -y install $1 >/dev/null
	if [ $? -ne 0 ]; then
		echo -e "${RED}Failed!${NONE}";
		exit 1;
	else
		echo -e "${GREEN}Successful.${NONE}";
	fi
}

echo -e "Welcome to the ${BLUE}SWCombine VM Server${NONE} setup script";

if [ ! -e "staging_prod.sql" ]; then
	echo -e "You are ${RED}missing${NONE} the required installation files. Please check that:";
	echo -e "\tstaging_prod.sql";
	echo -e "exist within the current directory and are readable";
	exit 1;
fi

# First, install mysql, if need be
dpkg-query -W --showformat='${Status}' mysql-server | grep "ok installed" >/dev/null
if [ $? -ne 0 ]; then
	echo -e "Please enter your ${BLUE}MySQL${NONE} root password (do not leave it blank):";
	read -s MYSQL_PW;
	echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_PW" | sudo debconf-set-selections
	echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PW" | sudo debconf-set-selections
	do_install "mysql-client mysql-server" "MySQL"
	echo "[client]\nuser=root\npassword=$MYSQL_PW\ndatabase=staging_prod\n" > ~/.my.cnf
else
	MYSQL_PW=`cat ~/.my.cnf | sed -n -e "s/password=\(.*\)/\1/p"`
	echo -e "${BLUE}MySQL${NONE} already installed, skipping..."
fi

# Then install php5 and the mysql driver
do_install "php5 php5-mysql" "PHP 5"

# Last, install svn because it isn't a default for some reason
do_install "subversion" "SVN"

# Configure the SWC repository at /swcombine
while true; do
	echo -e "Would you like to ${BLUE}download${NONE} the svn repository or ${BLUE}use an existing${NONE} local copy?\n\t[1] Download\n\t[2] Use existing."
	read dlsvn
	case $dlsvn in
		1 )
			echo -e "Downloading SVN repository to ${BLUE}/swcombine${NONE}. When prompted, enter your svn credentials";
			sudo mkdir /swcombine;
			sudo chown $REAL_USER /swcombine;
			svn co http://svn.swcombine.com/svn/swcombine/trunk /swcombine;
			break;;
		2 )
			echo -n -e "Enter the location of the existing SVN repository [${BLUE}/mnt/swcombine${NONE}]: "
			read svnpath
			if [ -d "$svnpath" ]; then
				if [ "$svnpath" = "/swcombine" ]; then
					echo -e "SWC already mounted correctly at ${BLUE}/swcombine${NONE}, skipping...";
				else
					echo -e "Creating symlink from ${BLUE}/swcombine${NONE} to ${BLUE}$svnpath${NONE}.";
					ln -s /swcombine $svnpath;
				fi;
			else
				echo -e "Supplied path ${BLUE}$svnpath${NONE} ${RED}does not exist${NONE}. Please check it and try again.";
				exit 1;
			fi;
			break;;
		* ) echo -e "${RED}Invalid selection${NONE}"
			;;
	esac
done

# Configure apache to point to /swcombine and process php
echo -e "Configuring ${BLUE}Apache and PHP${NONE}"
if [ -e "/etc/apache2/sites-enabled/apache2-swc.conf" ]; then
	echo -e "Configuration ${GREEN}detected${NONE}, skipping.";
else
	sudo cp /swcombine/libs/apache2-swc.conf /etc/apache2/sites-enabled
	sudo rm /etc/apache2/sites-enabled/000-default
	sudo chmod 0777 /etc/php5/apache2/php.ini
	echo "include_path = \".:/swcombine/libs\"" >> /etc/php5/apache2/php.ini
	sudo service apache2 restart
	echo -e "${GREEN}Successfully${NONE} configured apache and php";
fi

# Perform initial mysql configuration
while true; do
	echo -e "Would you like to import the MySQL database, overwriting your current one (y/n)?"
	echo -e "${BLUE}Note:${NONE} This step is required to set up path.php correctly the first time."
	read importmysql
	case $importmysql in
		[yY] )
			# Do actual DB import, makes use of ~/.my.cnf for auto-authentication
			echo -e "Importing ${BLUE}MySQL${NONE} database.";
			mysql < staging_prod.sql;
			echo -e "\nImport ${GREEN}complete${NONE}.";

			# Now, copy over path.php and fill in the actual mysql password chosen
			pushd /swcombine/libs
			cat path.template.php | sed -e "s/db\.pass', 'swc'/db.pass', '$MYSQL_PW'/" > path.php
			popd
			break;;
		[nN] )
			echo -e "${BLUE}Skipping${NONE} MySQL import.";
			break;;
		* )
			echo -e "${RED}Invalid${NONE} selection."
			;;
	esac
done

# Configure cron jobs
echo -e "Configuring ${BLUE}cron jobs${NONE}"
sudo crontab -u root -l 2>/dev/null | grep "swcombine" > /dev/null
if [ $? -ne 0 ]; then
	sudo crontab -u root -l | cat - /swcombine/libs/cron-swc.src | sudo crontab -u root -
	echo -e "${GREEN}Added${NONE} SWC jobs to crontab"
else
	echo -e "Cron jobs ${GREEN}already configured${NONE}."
fi

if [ ! -d /swcombine/logs ]; then
	sudo mkdir /swcombine/logs
	chmod 0777 /swcombine/logs
fi

# Install PHPUnit for running unit tests
echo -e "Configuring ${BLUE}PHPUnit${NONE}"
if [ -e "/usr/local/bin/phpunit" ]; then
	echo -e "PHPUnit ${GREEN}already installed${NONE}, skipping.";
else
	wget https://phar.phpunit.de/phpunit.phar;
	chmod +x phpunit.phar;
	sudo mv phpunit.phar /usr/local/bin/phpunit
	echo -e "PHPUnit ${GREEN}installed${NONE} to ${BLUE}/usr/local/bin/phpunit${NONE}"
fi

echo -e "${BLUE}SWC VM server${NONE} setup ${GREEN}complete${NONE}."
