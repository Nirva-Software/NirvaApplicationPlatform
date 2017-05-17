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

# ./create_site_wildcard.sh <provider_code> domain test_domain admin_domain test_admin_domain certificate_file certificate_key certificate_CA applicationName
[ "$#" -eq 9 ] || die "Usage: ./create_site_wildcard.sh <provider_code> domain test_domain admin_domain test_admin_domain certificate_file certificate_key certificate_CA applicationName"

CODE=$1
DOMAIN=$2
DOMAIN_RCT=$3
DOMAIN_ADMIN=$4
DOMAIN_RCT_ADMIN=$5
CERT=$6
CERT_KEY=$7
CERT_CA=$8
APPLICATION_NAME=$9

./create_site.sh "${CODE}.conf" "$DOMAIN" template.conf "$CERT" "$CERT_KEY" "$CERT_CA" "$APPLICATION_NAME"
./create_site.sh "${CODE}_test.conf" "$DOMAIN_RCT" template_test.conf "$CERT" "$CERT_KEY" "$CERT_CA" "$APPLICATION_NAME"
#./create_site.sh "${CODE}_admin.conf" "$DOMAIN_ADMIN" template_admin.conf "$CERT" "$CERT_KEY" "$CERT_CA" "$APPLICATION_NAME"
#./create_site.sh "${CODE}_test_admin.conf" "$DOMAIN_RCT_ADMIN" template_test_admin.conf "$CERT" "$CERT_KEY" "$CERT_CA" "$APPLICATION_NAME"
