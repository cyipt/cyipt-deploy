# cyipt-deploy

Scripts for installing CyIPT.

Uses bash, but ideally would be moved to Ansible/Chef/Docker/Puppet/whatever in future.


## Requirements

Written for Ubuntu Server 18.04 LTS.


## Timezone

```shell
# Check your machine is in the right timezone
# user@machine:~$
cat /etc/timezone

# If not set it using:
sudo dpkg-reconfigure tzdata
```


## Setup

Add this repository to a machine using the following, as your normal username (not root). In the listing the grouped items can usually be cut and pasted together into the command shell, others require responding to a prompt:

```shell
# Install git
# user@machine:~$
sudo apt-get -y install git

# Tell git who you are
# git config --global user.name "Your git username"
# git config --global user.email "Your git email"
# git config --global push.default simple
# git config --global credential.helper 'cache --timeout=86400'

# Clone the repo
git clone https://github.com/cyipt/cyipt-deploy.git

# Move it to the right place
sudo mv cyipt-deploy /opt
cd /opt/cyipt-deploy/
git config core.sharedRepository group

# Create a generic user - without prompting for e.g. office 'phone number
sudo adduser --gecos "" cyipt

# Create the rollout group
sudo addgroup rollout

# Add your username to the rollout group
sudo adduser `whoami` rollout

# The adduser command above can't add your existing shell process to the
# new rollout group; you may want to replace it by doing:
exec newgrp rollout

# Login
# user@other-machine:~$
ssh user@machine

# Set ownership and group
# user@machine:~$
sudo chown -R cyipt.rollout /opt/cyipt-deploy

# Set group permissions and add sticky group bit
sudo chmod -R g+w /opt/cyipt-deploy
sudo find /opt/cyipt-deploy -type d -exec chmod g+s {} \;
```


## PostgreSQL

### Authentication

The script will add permissions to `pg_hba.conf`, which is the authentication permissions file.  
`sudo pico -w /etc/postgresql/9.5/main/pg_hba.conf`  
* The order of the file is important. More specific configuration MUST be before the default entries, i.e. at the start.
* "Typically, earlier records will have tight connection match parameters and weaker authentication methods, while later records will have looser match parameters and stronger authentication methods."
* See examples at: https://www.postgresql.org/docs/9.5/auth-pg-hba-conf.html#EXAMPLE-PG-HBA.CONF
* A server may or may not have IPv6 connectivity running. So you may need to have both IPv4 and IPv6 configurations.

Check that you can connect from the command line:  
`psql -d cyipt -U cyipt`

Start/restart using:  
`sudo service postgresql start`

Ensure that PostgreSQL is running:  
`ps aux | grep postgres`

If not, check the PostgreSQL log file:  
`sudo tail -f /var/log/postgresql/postgresql-9.5-main.log`

### Data transfer to new server

To transfer PostgreSQL data to a new server, see:  
https://www.postgresql.org/docs/10/backup-dump.html

Data can be dumped out, compressed, using:  
`sudo -u postgres pg_dump cyipt -Z 9 > cyipt.sql.gz`

Data can be imported, uncompressing on the fly, using:  
`gunzip < cyipt.sql.gz | psql cyipt`

