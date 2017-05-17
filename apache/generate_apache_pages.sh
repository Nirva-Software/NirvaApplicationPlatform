#!/bin/bash

die () {
        echo -e >&2 "$@"
        exit 1
}

set -e # Exits at first failure
set -u # Exits when a non initialized variable is used

if [[ $EUID -ne 0 ]]; then
   die "This script must be run as root"
fi

# ./generate_apache_pages.sh <provider_code> applicationName domain
[ "$#" -eq 3 ] || die "Usage: ./generate_apache_pages.sh <provider_code> applicationName domain"

CODE=$1
APPLICATION_NAME=$2
DOMAIN=$3

OLD_REP=`pwd`

cd /var/www

if [ -d "$CODE" ]; then
  echo "Removing Old directory /var/www/$CODE"
  [ -d "${CODE}.bak" ] && rm -R "${CODE}.bak"
  mv "$CODE" "${CODE}.bak"
fi

cp -R template $CODE
sed -i "s/\\\${APPLICATION_NAME}/${APPLICATION_NAME}/g" $CODE/error.htm

cd $OLD_REP
