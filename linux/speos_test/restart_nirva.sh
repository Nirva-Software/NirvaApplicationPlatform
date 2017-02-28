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

# Variables
TO_EMAIL=saas.speos@nirva-software.com
FROM_EMAIL=$TO_EMAIL
NIRVA_SYSTEM_LOG=/home/nirva/log/nirva/Logs/SYSTEM/nvs.log
NIRVA_LOG_PWD=log_admin

# Log rotate
LOG_FILE="${HOME}/log/"`basename $0 .sh`".log"
MAXIMUM_LOG_SIZE=10240
LOG_FILE_SIZE=0
if [ -f $LOG_FILE ]
then
        LOG_FILE_SIZE=$(du -b "$LOG_FILE" | cut -f 1)
fi
if [ "$LOG_FILE_SIZE" -ge "$MAXIMUM_LOG_SIZE" ]
then
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

        mv $LOG_FILE "${LOG_FILE}.1"
        gzip "${LOG_FILE}.1"
fi

exec 1>>$LOG_FILE 2>&1

MAIL="/tmp/nv_restart_nirva_mail.txt"

sendMail() {
    rm -f $MAIL
    echo "To: ${TO_EMAIL}" > $MAIL
    echo "From: ${FROM_EMAIL}" >> $MAIL
    echo "Subject: $1"$'\n' >> $MAIL
    echo -e "$2" >> $MAIL
    echo "" >> $MAIL
    echo "" >> $MAIL
    echo "SYSTEM end trace is:" >> $MAIL
    echo "" >> $MAIL
    tail -n 50 "$NIRVA_SYSTEM_LOG" >> $MAIL
    /usr/sbin/ssmtp ${TO_EMAIL} < $MAIL
    rm -f $MAIL
}


date
#export PATH="${PATH:+$PATH:}/sbin:/usr/sbin"
stop=`date +%s`

#echo "PATH: ${PATH}"

echo "Raise SYSTEM logs to level 6"
$NIRVA/Bin/nvcc -u log_admin -w $NIRVA_LOG_PWD -z "NV_CMD='LOG:SET_OPTIONS' LOG='SYSTEM' SERVICE='SYSTEM' LEVEL='6'"

echo "Stop Nirva"
sudo service nirva stop
echo -n "Stopped at "
date
end_stop=`date +%s`

if [ $((end_stop - stop)) -gt 180 ]; then
    echo "Nirva server has been killed (Stopped took more than 3 minutes)."
    sendMail "[$HOSTNAME] Nirva server has been killed" "Nirva server has been killed during restart on $HOSTNAME."
fi
# Sleep for a while. The nvs process seams to be in zombi state for a few seconds before actually stopping.
sleep 10
PGREP_DEBUG=$(pgrep nvs)
if [ -n "$PGREP_DEBUG" ]; then
    PROCESSES="$(ps aux | grep nvs | grep -v grep)"
    echo -e "Nirva server was in zombie state.\npgrep returned:\n$PGREP_DEBUG\nnvs Processes:\n$PROCESSES\n"
    pkill -9 nvs
    sendMail "[$HOSTNAME] Nirva server was in zombie state" "Nirva server has been killed during restart on $HOSTNAME. It was probably in zombie state.\n\nProcess List:\n$PROCESSES\n"
fi

echo "Start Nirva"
sudo service nirva start

echo -n "Restart at "
date

echo "Sleep for 1 minute (time for Nirva server to start again) to update the log to previous level (1)"
sleep 60
$NIRVA/Bin/nvcc -u log_admin -w $NIRVA_LOG_PWD -z "NV_CMD='LOG:SET_OPTIONS' LOG='SYSTEM' SERVICE='SYSTEM' LEVEL='1'"
