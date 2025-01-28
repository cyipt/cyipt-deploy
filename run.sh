#!/bin/bash
# Installs the CyIPT system
# Written for Ubuntu 22.04 LTS Server

### Stage 1 - general setup

echo "#	CyIPT: install system"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#     This script must be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e

# Lock directory
lockdir=/var/lock/cyipt_outer
mkdir -p $lockdir

# Set a lock file; see: http://stackoverflow.com/questions/7057234/bash-flock-exit-if-cant-acquire-lock/7057385
(
	flock -n 900 || { echo '#	An installation is already running' ; exit 1; }


### CREDENTIALS ###

# Get the script directory see: http://stackoverflow.com/a/246128/180733
# The multi-line method of geting the script directory is needed to enable the script to be called from elsewhere.
SOURCE="${BASH_SOURCE[0]}"
DIR="$( dirname "$SOURCE" )"
while [ -h "$SOURCE" ]
do
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd )"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
SCRIPTDIRECTORY=$DIR
ScriptHome=$(readlink -f "${SCRIPTDIRECTORY}/")

# Define the location of the credentials file relative to script directory
configFile=$ScriptHome/.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -x $configFile ]; then
    echo "#	The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. $configFile

# Announce starting
echo "# CyIPT system installation $(date)"


## Main body

# Ensure a fully-patched system
apt-get -y update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove

# Create cyipt user
id -u cyipt || adduser --disabled-password --gecos "" cyipt

# Install basic utility software
apt-get -y install wget dnsutils man-db git nano bzip2 screen dos2unix mlocate
updatedb

# Install Apache (2.4), including htpasswd
apt-get -y install apache2 apache2-utils

# Enable core Apache modules
a2enmod rewrite
a2enmod headers
a2enmod ssl

# Install PHP (8.1)
apt-get -y install php php-cli php-mbstring
apt-get -y install libapache2-mod-php

# Install PostgreSQL
apt-get -y install postgresql postgresql-contrib
apt-get -y install php-pgsql

# Install PostgreSQL database and user
# Check connectivity using: `psql -h localhost cyipt cyipt -W` (where this is `psql database user`); -h localhost is needed to avoid "Peer authentication failed" error
database=cyipt
username=cyipt
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${username}';\"" | grep -q 1 || su - postgres -c "psql -c \"CREATE USER ${username} WITH PASSWORD '${password}';\""
su - postgres -c "psql -tAc \"SELECT 1 from pg_catalog.pg_database where datname = '${database}';\"" | grep -q 1 || su - postgres -c "createdb -O ${username} ${database}"
# Privileges should not be needed: "By default all public scemas will be available for regular (non-superuser) users." - https://stackoverflow.com/a/42748915/180733
# See also note that privileges (if relevant) should be on the table, not the database: https://stackoverflow.com/a/15522548/180733
#su - postgres -c "psql -tAc \"GRANT ALL PRIVILEGES ON DATABASE ${database} TO ${username};\""

# Install PostGIS (Postgres GIS extension)
apt-get -y install postgis
su - postgres -c "psql -d ${database} -tAc \"CREATE EXTENSION IF NOT EXISTS postgis;\""

# Enable postgres connectivity, adding to the start of the file, with IPv4 and IPv6 rules
if ! grep -q cyipt /etc/postgresql/14/main/pg_hba.conf; then
	sed -i '1 i\host  cyipt  cyipt  ::1/128       trust' /etc/postgresql/14/main/pg_hba.conf	# IPv6 rule, will end up as second line
	sed -i '1 i\host  cyipt  cyipt  127.0.0.1/32  trust' /etc/postgresql/14/main/pg_hba.conf	# IPv4 rule, will end up as first line
fi
sudo service postgresql restart

# NB To import data from a previous installation:
#  # Dump from existing:
#  sudo -i -u postgres
#  pg_dumpall > /tmp/alldbs-oldserver.sql
#  sudo gzip /tmp/alldbs-oldserver.sql
#  # On new server, after copying over the file:
#  sudo -i -u postgres
#  zcat /tmp/alldbs-oldserver.sql.gz | psql -U postgres	# Takes about 5-10 minutes, and will emit lines such as 'ALTER TABLE', 'COPY n', etc.

# Create site files directory
mkdir -p /var/www/cyipt/
chown -R cyipt:rollout /var/www/cyipt/
chmod g+ws /var/www/cyipt/

# Create site files directory
mkdir -p /var/www/popupCycleways/
chown -R cyipt:rollout /var/www/popupCycleways/
chmod g+ws /var/www/popupCycleways/

# Add VirtualHost
if [ ! -f /etc/apache2/sites-available/cyipt.conf ]; then
	cp -pr $ScriptHome/apache.conf /etc/apache2/sites-available/cyipt.conf
fi
a2ensite cyipt
# Apache is restarted below, once the certificate is present

# Let's Encrypt (free SSL certs), which will create a cron job
# See: https://www.digitalocean.com/community/tutorials/how-to-secure-apache-with-let-s-encrypt-on-ubuntu
# See: https://eff-certbot.readthedocs.io/en/latest/using.html
apt-get -y install certbot

# Create an HTTPS cert (without auto installation in Apache)
if [ ! -f /etc/letsencrypt/live/www.cyipt.bike/fullchain.pem ]; then
	email=info@
	email+=cyclestreets.net
	# If this fails, e.g. due to setting up the server before DNS transfer, copy in /etc/letsencrypt/live/www.cyipt.bike/ from the live server and then re-run the script
	certbot --agree-tos --no-eff-email certonly --keep-until-expiring --webroot -w /var/www/cyipt/ --email $email -d www.cyipt.bike -d cyipt.bike
fi

# Restart Apache
service apache2 restart

# Clone or update repo
if [ ! -d /var/www/cyipt/.git/ ]; then
	sudo -u cyipt  git clone https://github.com/cyipt/cyipt-website.git /var/www/cyipt/
	sudo -u cyipt  git clone https://github.com/cyclestreets/Leaflet.LayerViewer.git /var/www/cyipt/js/lib/Leaflet.LayerViewer/
	sudo -u cyipt  git clone --branch gh-pages https://github.com/cyipt/popupCycleways.git /var/www/popupCycleways/
else
	sudo -u cyipt  git -C /var/www/cyipt/ pull
	sudo -u cyipt  git -C /var/www/cyipt/js/lib/Leaflet.LayerViewer/ pull
	sudo -u cyipt  git -C /var/www/popupCycleways/ pull
fi
chmod -R g+w /var/www/cyipt/

# Add cronjob to update from Git regularly
cp $ScriptHome/cyipt.cron /etc/cron.d/cyipt
chown root:root /etc/cron.d/cyipt
chmod 644 /etc/cron.d/cyipt

# Add mailserver
# Exim
# Mail Transfer Agent (MTA); NB load before Python otherwise Ubuntu will choose Postfix
# See: https://help.ubuntu.com/lts/serverguide/exim4.html and http://manpages.ubuntu.com/manpages/hardy/man8/update-exim4.conf.8.html
# NB The config here is currently Debian/Ubuntu-specific
apt-get -y install exim4
if [ ! -e /etc/exim4/update-exim4.conf.conf.original ]; then
	cp -pr /etc/exim4/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf.original
	# NB These will deliberately overwrite any existing config; it is assumed that once set, the config will only be changed via this setup script (as otherwise it is painful during testing)
	sed -i "s/dc_eximconfig_configtype=.*/dc_eximconfig_configtype='internet'/" /etc/exim4/update-exim4.conf.conf
	sed -i "s/dc_other_hostnames=.*/dc_other_hostnames='cyipt.bike'/" /etc/exim4/update-exim4.conf.conf
	sed -i "s/dc_local_interfaces=.*/dc_local_interfaces=''/" /etc/exim4/update-exim4.conf.conf
	update-exim4.conf
	service exim4 start
fi
echo "IMPORTANT: Aliases need to be added to /etc/aliases"

# Enable firewall
apt-get -y install ufw
ufw logging low
ufw --force reset
ufw --force enable
ufw default deny
ufw allow ssh
ufw allow http
ufw allow https
ufw allow smtp
ufw reload
ufw status verbose

# Report completion
echo "#	Installing CyIPT system completed"

# Remove the lock file - ${0##*/} extracts the script's basename
) 900>$lockdir/${0##*/}

# End of file
