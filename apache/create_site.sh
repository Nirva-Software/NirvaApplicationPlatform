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

# ./create_site.sh mode <provider_code> domain certificate_file certificate_key certificate_CA applicationName
[ "$#" -eq 7 ] || die "Usage: ./create_site.sh test|prod <provider_code> domain certificate_file certificate_key certificate_CA applicationName"

MODE=$1
if [ "$MODE" != "prod" ]; then
	MODE=test
fi
CODE=$2
DOMAIN=$3
CERT=$4
CERT_KEY=$5
CERT_CA=$6
APPLICATION_NAME=$7

if [ ! -f "$CERT" ]; then
	if [ -f "/etc/apache2/ssl/$CERT" ]; then
		CERT="/etc/apache2/ssl/$CERT"
	else
		CERT="/etc/apache2/letsencrypt/certs/$CERT"
	fi
fi
if [ ! -f "$CERT_KEY" ]; then
	if [ -f "/etc/apache2/ssl/$CERT_KEY" ]; then
		CERT_KEY="/etc/apache2/ssl/$CERT_KEY"
	else
		CERT_KEY="/etc/apache2/letsencrypt/certs/$CERT_KEY"
	fi
fi
if [ ! -f "$CERT_CA" ]; then
	if [ -f "/etc/apache2/ssl/$CERT_CA" ]; then
		CERT_CA="/etc/apache2/ssl/$CERT_CA"
	else
		CERT_CA="/etc/apache2/letsencrypt/certs/$CERT_CA"
	fi
fi

OLD_REP=`pwd`

# Generate static pages for Apache
cd /var/www
if [ -d "${CODE}_${MODE}.conf" ]; then
  echo "Removing Old directory /var/www/${CODE}_${MODE}.conf"
  [ -d "${CODE}_${MODE}.conf.bak" ] && rm -R "${CODE}_${MODE}.conf.bak"
  mv "${CODE}_${MODE}.conf" "${CODE}_${MODE}.conf.bak"
fi
cp -R template ${CODE}_${MODE}.conf
sed -i "s/\\\${APPLICATION_NAME}/${APPLICATION_NAME}/g" ${CODE}_${MODE}.conf/error.htm

# Generate apache site from template
cd /etc/apache2/sites-available/

cp "${MODE}_apache_template.conf" ${CODE}_${MODE}.conf
sed -i "s/server_name/$DOMAIN/g" ${CODE}_${MODE}.conf
sed -i "s/\/var\/www\/site_folder/\/var\/www\/${CODE}_${MODE}.conf/g" ${CODE}_${MODE}.conf
sed -i "s~SSLCertificateFile /etc/apache2/ssl/certificate.crt~SSLCertificateFile $CERT~" ${CODE}_${MODE}.conf
sed -i "s~SSLCertificateKeyFile /etc/apache2/ssl/certificate.key~SSLCertificateKeyFile $CERT_KEY~" ${CODE}_${MODE}.conf
sed -i "s~SSLCACertificateFile /etc/apache2/ssl/CAcertificate.pem~SSLCACertificateFile $CERT_CA~" ${CODE}_${MODE}.conf

cd $OLD_REP
