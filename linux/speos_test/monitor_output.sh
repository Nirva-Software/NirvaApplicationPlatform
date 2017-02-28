#!/bin/bash
# To send email, first install ssmtp program :
#    apt-get install ssmtp
# and configure /etc/ssmtp/ssmtp.conf with the following parameters:
#    root=monitor@nirva-systems.com
#    mailhub=ssl0.ovh.net:465
#    UseTLS=YES
#    AuthUser=monitor@nirva-systems.com
#    AuthPass=<monitor password>
#    rewriteDomain=nirva-systems.com
#    hostname=<hostname>
#    FromLineOverride=YES
# For security:
#    chmod 640 /etc/ssmtp/ssmtp.conf
#    chown root:mail /etc/ssmtp/ssmtp.conf
#    usermod -a -G mail <your_user>
# and relog your user

VERBOSE="-v"

# Variables
TO_EMAIL=saas.speos@nirva-software.com
FROM_EMAIL=$TO_EMAIL
DEFAULT_PATH_PREFIX="/media/data/preprod/data"

# Log rotate
LOG_FILE="${HOME}/log/"`basename $0`".log"
COUNT=6
while [ $COUNT -gt 1 ]
do
    NEXT_COUNT=$((COUNT-1))
    if [ -f "${LOG_FILE}.${NEXT_COUNT}.gz" ]
    then
        mv "${LOG_FILE}.${NEXT_COUNT}.gz" "${LOG_FILE}.${COUNT}.gz"
    fi

    COUNT=$NEXT_COUNT
done
if [ -f "$LOG_FILE" ]
then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    gzip "${LOG_FILE}.1"
fi

exec 1>>"$LOG_FILE" 2>&1

MAIL="/tmp/nv_monitor_output_mail.txt"
MAIL_LOG="/tmp/nv_monitor_output_mail_log.txt"

touch $MAIL_LOG

sendMail() {
    rm -f $MAIL
    echo "To: ${TO_EMAIL}" > $MAIL
    echo "From: ${FROM_EMAIL}" >> $MAIL
    echo "Subject: $1"$'\n' >> $MAIL
    echo "$2" >> $MAIL
    echo "" >> $MAIL
    echo "" >> $MAIL
    cat $MAIL_LOG >> $MAIL
    echo "" >> $MAIL
    /usr/sbin/ssmtp ${TO_EMAIL} < $MAIL
    rm -f $MAIL
    rm -f $MAIL_LOG
}

date

PATH_PREFIX=$1
if [ -z $PATH_PREFIX ]
    then
    PATH_PREFIX=$DEFAULT_PATH_PREFIX
fi

echo "Base folder is $PATH_PREFIX"

# First archive output files of previous month
# ( + billing)
cd "${PATH_PREFIX}/output/archives"

if [ $? -ne 0 ]
    then
    echo "Invalid base folder!!"
    sendMail "[$HOSTNAME] Ouput folder monitoring" "Could not access the output archives folder '${PATH_PREFIX}/output/archives'."
    exit
fi

PREVIOUS_MONTH=`date --date="last month" +%Y/%m`
CURRENT_MONTH=`date +%Y/%m`

#echo "Billing for $PREVIOUS_MONTH"
echo "Information detail is:" > $MAIL_LOG

if [ -e "$PREVIOUS_MONTH" ]
    then
    echo "Already done."
else
	BATCH_CUR_MONTH=`echo "${CURRENT_MONTH//[\/]/-}-01"`
# Move files
    NUM_FILES=`find . -maxdepth 1 -type f ! -newermt ${BATCH_CUR_MONTH} | wc -l`

    echo "Files to move : $NUM_FILES"
    echo "Nb files in $PREVIOUS_MONTH: $NUM_FILES" >> $MAIL_LOG

    echo "Creating folder $PREVIOUS_MONTH"
    mkdir -p $PREVIOUS_MONTH
    echo "Folder created successfully!"

    if [ "$NUM_FILE" == "0" ]
    then
        echo "No files producted this month."
    else
        echo "Moving files strictly before ${BATCH_CUR_MONTH} to ${PREVIOUS_MONTH} (${NUM_FILES} files)"
        find . -maxdepth 1 -type f ! -newermt ${BATCH_CUR_MONTH} -exec mv -t $PREVIOUS_MONTH {} +
    fi

# Move batches
    NUM_BATCHES=`find batch -mindepth 1 -maxdepth 1 ! -newermt ${BATCH_CUR_MONTH} | wc -l`
    echo "Batches files to move : $NUM_BATCHES"
    echo "Nb batches files in $PREVIOUS_MONTH: $NUM_BATCHES" >> $MAIL_LOG

    if [ "$NUM_BATCHES" == "0" ]
    then
        echo "No batches producted this month."
    else
        echo "Moving batches files strictly before ${BATCH_CUR_MONTH} to ${PREVIOUS_MONTH} (${NUM_BATCHES} files)"
        find batch -mindepth 1 -maxdepth 1 ! -newermt ${BATCH_CUR_MONTH} -exec mv -t $PREVIOUS_MONTH {} +
    fi

fi

# Purge files
PURGE_DATE=`date --date="6 months ago" +%Y%m`

# Purge archived output folders older than 6 months
cd "${PATH_PREFIX}/output/archives"
if [ $? -ne 0 ]
    then
    echo "Invalid base folder!! (${PATH_PREFIX}/output/archives)"
    sendMail "[$HOSTNAME] Ouput folder monitoring" "Could not access the output archives folder '${PATH_PREFIX}/output/archives'."
    exit
fi

find . -mindepth 1 -maxdepth 1 -type d -printf "%f\0" | while read -d $'\0' F 
do
    if [[ "$F" < "${PURGE_DATE:0:4}" ]]
    then
        echo "$F < ${PURGE_DATE:0:4}... Removing folder..."
        rm -Rf $VERBOSE -- "$F"
        echo "Removing Output $F" >> $MAIL_LOG
    elif [[ "$F" == "${PURGE_DATE:0:4}" ]]
    then
        echo "$F == ${PURGE_DATE:0:4} parsing children..."

        find $F -mindepth 1 -maxdepth 1 -type d -printf "%f\0" | while read -d $'\0' FF 
        do
            if [[ "$FF" < "${PURGE_DATE:4:2}" ]]
            then
                echo "$FF < ${PURGE_DATE:4:2}... Removing folder $F/$FF..."
                rm -Rf $VERBOSE -- "$F/$FF"
                echo "Removing Output $F/$FF" >> $MAIL_LOG
            else
                echo "not ($FF < ${PURGE_DATE:4:2})... Keeping folder $F/$FF."
            fi
        done
    else
        echo "not ($F < ${PURGE_DATE:0:4})... Keeping folder."
    fi
done


# Purge archived tracking files older than 6 months
# in mail/archives
cd "${PATH_PREFIX}/tracking/mail/archives"
if [ $? -ne 0 ]
    then
    echo "Invalid base folder!! (${PATH_PREFIX}/tracking/mail/archives)"
    sendMail "[$HOSTNAME] Ouput folder monitoring" "Could not access the tracking archives folder '${PATH_PREFIX}/tracking/mail/archives'."
    exit
fi

NUM_FILES=0
while read -r -u3 -d $'\0' F
do
    FILE_MODIFIED_DATE=`date -r "$F" +%Y%m`
    if [[ "${F:0:6}" < "$PURGE_DATE" ]] && [[ "$FILE_MODIFIED_DATE" < "$PURGE_DATE" ]]
    then
        NUM_FILES=$((NUM_FILES+1))
#       echo "${F:0:6} < $PURGE_DATE... Removing file ($NUM_FILES)..."
        rm -f -- "$F"
        echo "Remove $F ($FILE_MODIFIED_DATE)"
#    else
##      echo "not (${F:0:6} < $PURGE_DATE)... Keeping file."
#       echo "Keeping $F ($FILE_MODIFIED_DATE)"
    fi
done 3< <(find . -mindepth 1 -maxdepth 1 -type f -printf "%f\0")
echo "Nb Tracking Files removed: $NUM_FILES" >> $MAIL_LOG


# in external/out
cd "${PATH_PREFIX}/tracking/external/out"
if [ $? -ne 0 ]
    then
    echo "Invalid base folder!! (${PATH_PREFIX}/tracking/external/out)"
    sendMail "[$HOSTNAME] Ouput folder monitoring" "Could not access the external tracking archives folder '${PATH_PREFIX}/tracking/external/out'."
    exit
fi
NUM_FILES=0
while read -r -u3 -d $'\0' F
do
    FILE_MODIFIED_DATE=`date -r "$F" +%Y%m`
    if [[ "${F:0:6}" < "$PURGE_DATE" ]] && [[ "$FILE_MODIFIED_DATE" < "$PURGE_DATE" ]]
    then
        NUM_FILES=$((NUM_FILES+1))
#       echo "${F:0:6} < $PURGE_DATE... Removing file..."
        rm -f -- "$F"
        echo "Remove $F ($FILE_MODIFIED_DATE)"
#    else
##      echo "not (${F:0:6} < $PURGE_DATE)... Keeping file."
#       echo "Keeping $F ($FILE_MODIFIED_DATE)"
    fi
done 3< <(find . -mindepth 1 -maxdepth 1 -type f -printf "%f\0")
echo "Nb Tracking Files removed: $NUM_FILES" >> $MAIL_LOG

sendMail "[$HOSTNAME] Ouput folder monitoring" "Purge folders successfully."

echo -n "Ended at "
date
