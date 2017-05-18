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

# ./create_site_wildcard.sh mode <provider_code> domain test_domain certificate_file certificate_key certificate_CA applicationName
[ "$#" -eq 8 ] || die "Usage: ./create_site_wildcard.sh test|prod <provider_code> domain test_domain certificate_file certificate_key certificate_CA applicationName"

MODE=$1
if [ "$MODE" != "prod" ]; then
	MODE=test
fi
CODE=$2
DOMAIN=$3
CERT=$5
CERT_KEY=$6
CERT_CA=$7
APPLICATION_NAME=$8

./create_site.sh "$MODE" "$CODE" "$DOMAIN" "$CERT" "$CERT_KEY" "$CERT_CA" "$APPLICATION_NAME"
