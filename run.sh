#!/bin/bash
# Installs the CyIPT system

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

# Use this to remove the ../ to get the repository root; assumes the script is always down one level
ScriptHome=$(readlink -f "${SCRIPTDIRECTORY}/..")

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




# Report completion
echo "#	Installing CyIPT system completed"

# Remove the lock file - ${0##*/} extracts the script's basename
) 900>$lockdir/${0##*/}

# End of file