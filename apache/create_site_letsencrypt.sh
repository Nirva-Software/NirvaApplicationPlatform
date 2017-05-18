#!/bin/bash

die () {
        echo -e >&2 "$@"
        exit 1
}

set -e # Exits at first failure

if [[ $EUID -ne 0 ]]; then
   die "This script must be run as root"
fi

# ./create_site_letsencrypt.sh mode <provider_code> domain applicationName letsencrypt_domain
[ "$#" -eq 4 ] || [ "$#" -eq 5 ] || die "Usage: ./create_site_letsencrypt.sh test|prod <provider_code> domain applicationName\nor ./create_site_letsencrypt.sh test|prod <provider_code> domain applicationName letsencrypt_domain\nif the letsencrypt configuration is common with another sub-domain."

MODE=$1
if [ "$MODE" != "prod" ]; then
	MODE=test
fi
CODE=$2
DOMAIN=$3
APPLICATION_NAME=$4
CERT_DOMAIN=$5
[[ -z "$CERT_DOMAIN" ]] && CERT_DOMAIN="$DOMAIN"

./create_site.sh "$MODE" "$CODE" "$DOMAIN" "$CERT_DOMAIN/fullchain.pem" "$CERT_DOMAIN/privkey.pem" "$CERT_DOMAIN/cert.pem" "$APPLICATION_NAME"
