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

# ./create_site.sh <provider_code> domain site_template certificate_file certificate_key certificate_CA applicationName
[ "$#" -eq 7 ] || die "Usage: ./create_site.sh <provider_code> domain site_template certificate_file certificate_key certificate_CA applicationName"

CODE=$1
DOMAIN=$2
TEMPLATE=$3
CERT=$4
CERT_KEY=$5
CERT_CA=$6
APPLICATION_NAME=$7

if [ ! -f "$CERT" ]; then
	CERT="/etc/apache2/ssl/$CERT"
fi
if [ ! -f "$CERT_KEY" ]; then
	CERT_KEY="/etc/apache2/ssl/$CERT_KEY"
fi
if [ ! -f "$CERT_CA" ]; then
	CERT_CA="/etc/apache2/ssl/$CERT_CA"
fi

OLD_REP=`pwd`

# Generate static pages for Apache
./generate_apache_pages.sh "$CODE" "$APPLICATION_NAME" "$DOMAIN"

cd /etc/apache2/sites-available/

cp $TEMPLATE $CODE
sed -i "s/server_name/$DOMAIN/g" $CODE
sed -i "s/\/var\/www\/site_folder/\/var\/www\/$CODE/g" $CODE
sed -i "s~SSLCertificateFile /etc/apache2/ssl/certificate.crt~SSLCertificateFile $CERT~" $CODE
sed -i "s~SSLCertificateKeyFile /etc/apache2/ssl/certificate.key~SSLCertificateKeyFile $CERT_KEY~" $CODE
sed -i "s~SSLCACertificateFile /etc/apache2/ssl/CAcertificate.pem~SSLCACertificateFile $CERT_CA~" $CODE

cd $OLD_REP
