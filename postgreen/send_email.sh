#!/bin/bash
# To send email, first install ssmtp program :
#    apt-get install ssmtp
# and configure /etc/ssmtp/ssmtp.conf with the following parameters:
#    root=<Main email address>
#    mailhub=<smtp server, for example: ssl0.ovh.net:465>
#    UseTLS=YES
#    AuthUser=<Login user for the SMTP server>
#    AuthPass=<Password of the user>
#    rewriteDomain=<domain name for the FROM addresses>
#    hostname=<hostname>
#    FromLineOverride=YES
# For security:
#    chmod 640 /etc/ssmtp/ssmtp.conf
#    chown root:mail /etc/ssmtp/ssmtp.conf
#    usermod -a -G mail <your_user>
# and relog your user

# Variables
TO_EMAIL=some@email.com
FROM_EMAIL=$TO_EMAIL

MAIL="/tmp/send_email_$$.txt"

rm -f $MAIL
echo "To: ${TO_EMAIL}" > $MAIL
echo "From: ${FROM_EMAIL}" >> $MAIL
echo "Subject: $1" >> $MAIL
echo "Mime-Version: 1.0;" >> $MAIL
echo -e 'Content-Type: text/html; charset="UTF-8";\n' >> $MAIL
echo -e "$2" >> $MAIL
echo "" >> $MAIL
/usr/sbin/ssmtp ${TO_EMAIL} < $MAIL
rm -f $MAIL
