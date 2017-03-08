#!/bin/bash

# Load parameters
if [ $# -ne 3 ]; then
	echo "Usage: extract_output.sh <creation_date_to_extract> <What to find in the xml file> <create tar file>" 1>&2
	echo 'For example: extract_output.sh 20170228 "<name>MARCO POLO FOODS</name>" "../20170228.tgz"' 1>&2
	echo 'Another example: extract_output.sh 2017/01/20170115 "<login>marco_polo_foods:polling</login>" "/home/nirva/temp/20170115-marcopolo.tgz"' 1>&2
	exit 1
fi

DATE=$1
FIND_STR="$2"
FILEPATH="$3"

if [ -e "$FILEPATH" ]; then
	echo "File '$FILEPATH' already exist!" 1>&2
	exit 1
fi

for i in `grep -nw ${DATE}*.xml -e "${FIND_STR}" | cut -d: -f1`; do echo "${i%.*}.xml"; echo "${i%.*}.pdf"; done | tar -czvf "${FILEPATH}" -T -
