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
	echo -e "[client]\nuser=root\npassword=$MYSQL_PW\n" > ~/.my.cnf
else
	MYSQL_PW=`cat ~/.my.cnf | sed -n -e "s/password=\(.*\)/\1/p"`
	echo -e "${BLUE}MySQL${NONE} already installed, skipping..."
fi

# Then install php5 and the mysql driver
do_install "php5 php5-mysql" "PHP 5"

# Make sure git is installed/updated
do_install "git" "git"

# Configure the SWC repository at /swcombine
while true; do
	echo -e "Would you like to ${BLUE}download${NONE} the git repository or ${BLUE}use an existing${NONE} local copy?\n\t[1] Download\n\t[2] Use existing."
	read dlgit
	case $dlgit in
		1 )
			echo -e "Downloading git repository to ${BLUE}/swcombine${NONE}. When prompted, enter your git credentials (this will happen twice)";
			sudo mkdir /swcombine;
			sudo chown $REAL_USER /swcombine;
			git clone http://svn.swcombine.com/git/swcombine.git /swcombine;
			pushd /swcombine
			git config credential.helper store
			echo -e "Enter your developer username";
			read gitname
			git config user.name $gitname
			git config user.email ${gitname}@swcombine.com
			git fetch origin
			popd
			break;;
		2 )
			echo -n -e "Enter the location of the existing git repository checkout [${BLUE}/mnt/swcombine${NONE}]: "
			read gitpath
			if [ -d "$gitpath" ]; then
				if [ "$gitpath" = "/swcombine" ]; then
					echo -e "SWC already mounted correctly at ${BLUE}/swcombine${NONE}, skipping...";
				else
					echo -e "Creating symlink from ${BLUE}/swcombine${NONE} to ${BLUE}$gitpath${NONE}.";
					ln -s /swcombine $gitpath;
				fi;
			else
				echo -e "Supplied path ${BLUE}$gitpath${NONE} ${RED}does not exist${NONE}. Please check it and try again.";
				exit 1;
			fi;
			break;;
		* ) echo -e "${RED}Invalid selection${NONE}"
			;;
	esac
done

# Configure hooks repository in ~/hooks
pushd ~
git clone http://svn.swcombine.com/git/hooks.git
popd

# Configure apache to point to /swcombine and process php
echo -e "Configuring ${BLUE}Apache and PHP${NONE}"
if [ -e "/etc/apache2/sites-enabled/apache2-swc.conf" ]; then
	echo -e "Configuration ${GREEN}detected${NONE}, skipping.";
else
	sudo cp /swcombine/libs/apache2-swc.conf /etc/apache2/sites-enabled
	sudo rm /etc/apache2/sites-enabled/000-default
	sudo chmod 0777 /etc/php5/apache2/php.ini
	echo "include_path = \".:/swcombine/libs\"" >> /etc/php5/apache2/php.ini
	sudo chmod 0777 /etc/php5/cli/php.ini
        echo "include_path = \".:/swcombine/libs\"" >> /etc/php5/cli/php.ini
	sudo service apache2 restart
	echo -e "${GREEN}Successfully${NONE} configured apache and php";
fi

# Perform initial mysql configuration
CREATE_DB=0
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

			CREATE_DB=1

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

cat ~/.my.cnf | sed -n -e "/database/p" | grep "database" > /dev/null
if [ ($? -ne 0) -a ($CREATE_DB -ne 0) ]; then
	echo -e "database=staging_prod\n" >> ~/.my.cnf
fi

# Install Nodejs for build environment
do_install "curl" "cURL"
curl -sL https://deb.nodesource.com/setup | sudo bash -
do_install "nodejs" "Node.js"
sudo npm install -g less
sudo npm install -g less-plugin-clean-css

# Configure build script stuff
pushd /swcombine/build
cp path.sh.template path.sh
if [ -z $SWC_ROOT ]; then
	echo "export SWC_ROOT=/swcombine" >> ~/.bashrc
	echo "export PATH=\$PATH:~/hooks/cmds" >> ~/.bashrc
	export PATH=\$PATH:~/hooks/cmds
fi
popd

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

# Configure some stuff in /tmp that we expect to exist, apparently
# Doesn't seem to be expected anymore
#mkdir /tmp/feeds
#touch /tmp/feeds/gns_flashnews.xml
#sudo chown -R www-data:www-data /tmp/feeds
#sudo chmod 0777 -R /tmp/feeds

# Run build once to ensure that the site will look decent when it is loaded
echo -e "Running ${BLUE}git swc build${NONE} to create initial stylesheets"
git swc build

echo -e "${BLUE}SWC VM server${NONE} auto setup ${GREEN}complete${NONE}."

# Tell user about remaining manual setup
if [ $CREATE_DB -ne 0 ]; then
	echo -e "Now go to /swcombine/database/schema and run the SQL files there starting at 63."
	echo -e "This can be done with 'mysql < {name of file}'."
	echo -e "Then go to /swcombine/database/scripts and running the following php scripts with 'php -f {name of file}'."
	echo -e "hostileOwner.php"
	echo -e "newPrivScript.php"
	echo -e "Finally, go to /swcombine/database/vm-schema and run create_admin.sql in the same way as above."
	echo -e "This will allow you to login with 'admin@localhost' and '_PASS_'."
	
	echo -e "${BLUE}SWC VM server${NONE} setup will then be ${GREEN}complete${NONE}."
fi
