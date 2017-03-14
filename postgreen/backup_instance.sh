#!/bin/bash

###########################
#### INITIALIZE SCRIPT ####
###########################

SCRIPTPATH=$(cd ${0%/*} && pwd -P)

# Log rotation management, and default output to log
LOG_FILE="${HOME}/log/"`basename $0 .sh`".log"
"${SCRIPTPATH}/log_rotation.sh" "$LOG_FILE"

exec 8>&1 9>&2 1>>$LOG_FILE 2>&1 # Backup the stdout and stderr, to revert the change for "backup" mode.

##################################
# FUNCTIONS FOR ERROR MANAGEMENT #
##################################

SEND_EMAIL="${SCRIPTPATH}/send_email.sh"
INSTANCE=$HOSTNAME
ERROR_CONTENT=
function logError()
{
	MODE=$1
	INFO=$2
	EXTRA=$3
	ERROR_CONTENT="${ERROR_CONTENT}\n<p style=\"color:"
	if [[ $MODE == warning ]]; then
		ERROR_CONTENT="${ERROR_CONTENT}orange"
	else
		ERROR_CONTENT="${ERROR_CONTENT}red"
	fi
	ERROR_CONTENT="${ERROR_CONTENT}\">${INFO}<br/>${EXTRA}</p>"
}
function exitGracefully()
{
	# Catch the original error code, to propagate it.
	ERROR_CODE=$?
	trap - SIGTERM # Remove the SIGTERM trap. This is to avoid to loop on the kill/traps because of the future 'kill -- -$$' command.
	if [[ "$ERROR_CODE" -eq 0 ]]; then
		# This is the standard exit. We close everything properly.
		echo "ROLLBACK;" >&3

		echo "\q" >&3

		timeout 10 bash -c -- 'while true; do if read line ; then if [[ "$line" == "ROLLBACK" ]]; then echo "$line"; break; else echo "$line"; fi; fi;done' <"${FIFO_OUTPUT}"
		RETVAL=$?

		if [[ "$RETVAL" -eq 124 ]]; then
			# Error in the backup, kill the connection...
			echo "Backup failed when unlocking, kill the pgsql connection...";
			logError error "The lock connection to database could not be released... Kill it, but you have to check the log to see what went wrong..." "Timeout return: $RETVAL"
			kill -9 ${SUB_PID}
		fi

		echo "exit" >&3
		
		echo "Done."
	elif [ ${SUB_PID+x} ]; then # This tests if the variable is not set at all...
		# This is the error exit, and the ssh connection was opened. We try to close everything properly and force the kill...
		echo "Backup failed, kill the pgsql connection...";
		echo "\q" >&3
	fi
	# We will kill the children, but this includes killing ourselves... So trap the kill to exit with the desired exit code.
	trap "cleanupAndExit $ERROR_CODE" SIGTERM
	kill -- -$$ # Kill ourselves and the sub processes (ssh connection).
}
function cleanupAndExit()
{
	ERROR_CODE=$1
	# Remove the FIFO handles if they have been created
	if [ -z ${FIFO_FILE+x} ]; then rm "${FIFO_FILE}"; fi
	if [ -z ${FIFO_OUTPUT+x} ]; then rm "${FIFO_OUTPUT}"; fi

	# Send the email if there is an email content...
	if [ -n "$ERROR_CONTENT" ]; then # This tests if the variable is not empty
		${SEND_EMAIL} "[$INSTANCE] Backup issues..." "<html>$ERROR_CONTENT</html>"
	else
		${SEND_EMAIL} "[$INSTANCE] Backup" "<html><p>Backup completed successfully!</p></html>"
	fi

	echo "Cleanup done. Exit with $ERROR_CODE."
	exit $ERROR_CODE;
}
trap "exitGracefully" EXIT # SIGINT SIGTERM EXIT


###########################
####### LOAD CONFIG #######
###########################

while [ $# -gt 0 ]; do
        case $1 in
                -c)
                        if [ -r "$2" ]; then
                                CONFIG_FILE_PATH="$2"
                                shift 2
                        else
                                echo "Unreadable config file \"$2\"" 1>&2
                                exit 1
                        fi
                        ;;
				backup)
						echo "running in backup mode"...
						SEND_EMAIL=echo
						exec 1>&8 2>&9
						BACKUP_MODE=backup
						if [[ "$2" == "cleanup" ]]; then
							shift 1
							BACKUP_MODE=cleanup
						fi
						shift 1
						;;
                *)
                        echo "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done

if [ -z $CONFIG_FILE_PATH ]; then
        CONFIG_FILE_PATH="${SCRIPTPATH}/backup.config"
fi

if [ ! -r ${CONFIG_FILE_PATH} ] ; then
        echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
        exit 1
fi

source "${CONFIG_FILE_PATH}"

###########################
#### PRE-BACKUP CHECKS ####
###########################

# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ]; then
	echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
	exit 1
fi


###########################
### INITIALISE DEFAULTS ###
###########################

TIME="`date -u +\%H:\%M:00`Z"
if [ ! $HOSTNAME ]; then
	HOSTNAME="localhost"
fi;

if [ ! $USERNAME ]; then
	USERNAME="postgres"
fi;

if [ ! $OVH_CLIENT ]; then
	CURRENT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	OVH_CLIENT="$CURRENT_PATH/ovh-api-bash-client.sh"
fi;
#HOST_PARAM=-h 127.0.0.1

###########################
#### BACKUP  FUNCTIONS ####
###########################

function nas_snapshot()
{
	SUFFIX=$1
	SNAP_NAME="`date +\%Y-\%m-\%d`$SUFFIX"

	echo "Making snapshot for $SNAP_NAME"

	if [ $SUFFIX = "-monthly" ]
	then
		EXPIRATION_DATE="`date --date="-10 day" +\%Y-\%m-\%d`$SUFFIX"
	elif [ $SUFFIX = "-weekly" ]
	then
		EXPIRATION_DATE="`date --date="-${WEEKS_TO_KEEP} week" +\%Y-\%m-\%d`$SUFFIX"
	elif [ $SUFFIX = "-daily" ]
	then
		EXPIRATION_DATE="`date --date="-${DAYS_TO_KEEP} day" +\%Y-\%m-\%d`$SUFFIX"
	else
		# Set to few days in the past, to be sure to not remove the current backup...
		EXPIRATION_DATE="`date --date="-2 day" +\%Y-\%m-\%d`$SUFFIX"
	fi

	# Parse the NAS that contains partitions to backup
	echo -e "\n\nPerforming snapshots"
	echo -e "--------------------------------------------\n"
 
	for NAS in ${NAS_PARTITION_LIST//,/ }
	do
		# Get the NAS name
		NAS_NAME="${NAS%:*}"
		PARTITION_LIST="${NAS#*:}"
		for PARTITION in ${PARTITION_LIST//\// }
		do
	        echo "Snapshot of $NAS_NAME/$PARTITION"
			RES=`${OVH_CLIENT} --method POST --url "/dedicated/nasha/$NAS_NAME/partition/$PARTITION/customSnapshot" --data '{"name": "'${SNAP_NAME}'"}'`
			if [[ "$RES" != 200* ]]; then
				# Creating the snapshot failed...
				echo "Snapshot failed with error $RES"
				logError warning "Cannot create snapshot for $NAS_NAME/$PARTITION" "$RES"
			fi

			echo "Cleaning old backups before $EXPIRATION_DATE"
			OLD_SNAPSHOTS=`${OVH_CLIENT} --method GET --url "/dedicated/nasha/$NAS_NAME/partition/$PARTITION/customSnapshot"`
			if [[ "$OLD_SNAPSHOTS" == 200* ]]; then
				SNAPSHOT_LIST=${OLD_SNAPSHOTS%]}
				SNAPSHOT_LIST=${SNAPSHOT_LIST#*[}
				SNAPSHOT_LIST=${SNAPSHOT_LIST:1:-1}

				for SNAP in ${SNAPSHOT_LIST//\",\"/ }; do
					if [[ "$SNAP" == *$SUFFIX ]]; then
						if [[ "$SNAP" < "$EXPIRATION_DATE" ]]; then
							echo -e "\tRemoving $SNAP"
							RES=`${OVH_CLIENT} --method DELETE --url "/dedicated/nasha/$NAS_NAME/partition/$PARTITION/customSnapshot/$SNAP"`
							if [[ "$RES" != 200* ]]; then
								# Deleting the snapshot failed...
								echo "Deleting snapshot $NAS_NAME/$PARTITION failed with error $RES"
								logError error "Deleting snapshot $NAS_NAME/$PARTITION failed" "$RES"
							fi
						else
							echo -e "\t$SNAP: keeping snapshot"
						fi
					fi
				done
			else
				echo -e "Error in snapshot list. Returned is $OLD_SNAPSHOTS.\nContinue to next backups..."
				logError error "Cannot list snapshots for $NAS_NAME/$PARTITION" "$OLD_SNAPSHOTS"
			fi
		done
	done

	# Ensure that the snapshots have been made
	echo -e "\nEnsure snapshots have been made"
	echo -e "--------------------------------------------\n"
	for NAS in ${NAS_PARTITION_LIST//,/ }
	do
		# Get the NAS name
		NAS_NAME="${NAS%:*}"
		PARTITION_LIST="${NAS#*:}"
		for PARTITION in ${PARTITION_LIST//\// }
		do
			while true; do
				echo -n "Checking snapshot '$NAS_NAME/$PARTITION/${SNAP_NAME}' has been created... "
				RES=`${OVH_CLIENT} --method POST --url "/dedicated/nasha/$NAS_NAME/partition/$PARTITION/customSnapshot" --data '{"name": "'${SNAP_NAME}'"}'`
				if [[ "$RES" == 400* ]]; then
					# Snapshot correctly created
					echo "OK"
					break;
				elif [[ "$RES" == 404* ]]; then
					# Snapshot is processing. Sleep for 10s.
					echo "still processing. Will check again in 10s."
					sleep 10;
				else
					# Unknown result! Continue with others but raise error
					echo "Unkown error!! Continue but log to raise the error..."
					logError error "Cannot ensure that snapshot was created for $NAS_NAME/$PARTITION" "$RES"
					break;
				fi
			done
		done
	done
}
function nas_cleanup_snapshot()
{
	SUFFIX=$1

	echo "Cleanup snapshot for $SUFFIX"

	if [ $SUFFIX = "-monthly" ]
	then
		EXPIRATION_DATE="`date --date="-10 day" +\%Y-\%m-\%d`$SUFFIX"
	elif [ $SUFFIX = "-weekly" ]
	then
		EXPIRATION_DATE="`date --date="-${WEEKS_TO_KEEP} week" +\%Y-\%m-\%d`$SUFFIX"
	elif [ $SUFFIX = "-daily" ]
	then
		EXPIRATION_DATE="`date --date="-${DAYS_TO_KEEP} day" +\%Y-\%m-\%d`$SUFFIX"
	else
		# Set to the future, to be sure to remove all previous backups, including today...
		EXPIRATION_DATE="`date --date="+1 day" +\%Y-\%m-\%d`$SUFFIX"
	fi

	# Parse the NAS that contains partitions to backup
	echo -e "\n\nPerforming snapshots"
	echo -e "--------------------------------------------\n"
 
	for NAS in ${NAS_PARTITION_LIST//,/ }
	do
		# Get the NAS name
		NAS_NAME="${NAS%:*}"
		PARTITION_LIST="${NAS#*:}"
		for PARTITION in ${PARTITION_LIST//\// }
		do
			echo "Cleaning old backups before $EXPIRATION_DATE"
			OLD_SNAPSHOTS=`${OVH_CLIENT} --method GET --url "/dedicated/nasha/$NAS_NAME/partition/$PARTITION/customSnapshot"`
			if [[ "$OLD_SNAPSHOTS" == 200* ]]; then
				# First clean the response to get only the list of backups. The response is something like: 200 ["snap1","snap2"]
				SNAPSHOT_LIST=${OLD_SNAPSHOTS%]}
				SNAPSHOT_LIST=${SNAPSHOT_LIST#*[}
				SNAPSHOT_LIST=${SNAPSHOT_LIST:1:-1}

				for SNAP in ${SNAPSHOT_LIST//\",\"/ }; do
					if [[ "$SNAP" == *$SUFFIX ]]; then
						if [[ "$SNAP" < "$EXPIRATION_DATE" ]]; then
							echo -e "\tRemoving $SNAP"
							RES=`${OVH_CLIENT} --method DELETE --url "/dedicated/nasha/$NAS_NAME/partition/$PARTITION/customSnapshot/$SNAP"`
							if [[ "$RES" != 200* ]]; then
								# Deleting the snapshot failed...
								echo "Deleting snapshot $NAS_NAME/$PARTITION failed with error $RES"
								logError error "Deleting snapshot $NAS_NAME/$PARTITION failed" "$RES"
							fi
						else
							echo -e "\t$SNAP: keeping snapshot"
						fi
					fi
				done
			else
				echo -e "Error in snapshot list. Returned is $OLD_SNAPSHOTS.\nContinue to next backups..."
				logError error "Cannot list snapshots for $NAS_NAME/$PARTITION" "$OLD_SNAPSHOTS"
			fi
		done
	done
}

function db_backups()
{
	SUFFIX=$1
	FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`$SUFFIX/"
 
	echo "Making backup directory in $FINAL_BACKUP_DIR"
 
	if ! mkdir -p $FINAL_BACKUP_DIR; then
		echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
		logError error "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" ""
		exit 1;
	fi;
 
 
	###########################
	### SCHEMA-ONLY BACKUPS ###
	###########################
 
	for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }
	do
	        SCHEMA_ONLY_CLAUSE="$SCHEMA_ONLY_CLAUSE or datname ~ '$SCHEMA_ONLY_DB'"
	done
 
	SCHEMA_ONLY_QUERY="select datname from pg_database where false $SCHEMA_ONLY_CLAUSE order by datname;"
 
	echo -e "\n\nPerforming schema-only backups"
	echo -e "--------------------------------------------\n"
 
	SCHEMA_ONLY_DB_LIST=`ssh ${HOSTNAME} "psql ${HOST_PARAM} -U \"$USERNAME\" -At -c \"$SCHEMA_ONLY_QUERY\" postgres"`
 
	echo -e "The following databases were matched for schema-only backup:\n${SCHEMA_ONLY_DB_LIST}\n"
 
	for DATABASE in $SCHEMA_ONLY_DB_LIST
	do
	        echo "Schema-only backup of $DATABASE"
 
	        if ! ssh ${HOSTNAME} "pg_dump -Fp -s ${HOST_PARAM} -U \"$USERNAME\" \"$DATABASE\" | gzip -c" > $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.gz.in_progress; then
	                echo "[!!ERROR!!] Failed to backup database schema of $DATABASE" 1>&2
					logError error "[!!ERROR!!] Failed to backup database schema of $DATABASE" ""
	        else
	                mv $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.gz
	        fi
	done
 
 
	###########################
	###### FULL BACKUPS #######
	###########################
 
	for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }
	do
		EXCLUDE_SCHEMA_ONLY_CLAUSE="$EXCLUDE_SCHEMA_ONLY_CLAUSE and datname !~ '$SCHEMA_ONLY_DB'"
	done
 
	FULL_BACKUP_QUERY="select datname from pg_database where not datistemplate and datallowconn $EXCLUDE_SCHEMA_ONLY_CLAUSE order by datname;"
 
	echo -e "\n\nPerforming full backups"
	echo -e "--------------------------------------------\n"
 
	for DATABASE in `ssh ${HOSTNAME} "psql ${HOST_PARAM} -U \"$USERNAME\" -At -c \"$FULL_BACKUP_QUERY\" postgres"`
	do
		if [ $ENABLE_PLAIN_BACKUPS = "yes" ]
		then
			echo "Plain backup of $DATABASE"
 
			if ! ssh ${HOSTNAME} "pg_dump -Fp ${HOST_PARAM} -U \"$USERNAME\" \"$DATABASE\" | gzip -c" > $FINAL_BACKUP_DIR"$DATABASE".sql.gz.in_progress; then
				echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
				logError error "[!!ERROR!!] Failed to produce plain backup database $DATABASE" ""
			else
				mv $FINAL_BACKUP_DIR"$DATABASE".sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE".sql.gz
			fi
		fi
 
		if [ $ENABLE_CUSTOM_BACKUPS = "yes" ]
		then
			echo "Custom backup of $DATABASE"
 
			if ! ssh ${HOSTNAME} "pg_dump -Fc ${HOST_PARAM} -U \"$USERNAME\" \"$DATABASE\"" > $FINAL_BACKUP_DIR"$DATABASE".custom.in_progress; then
				echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE" 1>&2
				logError error "[!!ERROR!!] Failed to produce custom backup database $DATABASE" ""
			else
				mv $FINAL_BACKUP_DIR"$DATABASE".custom.in_progress $FINAL_BACKUP_DIR"$DATABASE".custom
			fi
		fi
 
	done
 
	echo -e "\nAll database backups complete!"
}


###########################
###### ACQUIRE  LOCK ######
###########################

FIFO_FILE=/tmp/backup_fifo
FIFO_OUTPUT=/tmp/backup_fifo_out
mkfifo "${FIFO_FILE}"
mkfifo "${FIFO_OUTPUT}"
(ssh ${HOSTNAME} <"${FIFO_FILE}" >"${FIFO_OUTPUT}") &

SUB_PID=$!

echo "Subshell: ${SUB_PID}#"

exec 3> "${FIFO_FILE}";

echo "psql ${HOST_PARAM} -U \"$USERNAME\" \"$LOCK_DATABASE\"" >&3
echo "BEGIN;" >&3
# The locked tables are the ones with storage content
echo "LOCK TABLE ${LOCK_TABLES} IN EXCLUSIVE MODE;" >&3

timeout 60 bash -c -- 'while true; do if read line ; then if [[ "$line" == "LOCK TABLE" ]]; then echo "$line"; break; else echo "$line"; fi; fi;done' <"${FIFO_OUTPUT}"
RETVAL=$?

echo "Timeout returns: $RETVAL#"
if [[ "$RETVAL" -eq 124 ]]; then
	# Cannot get lock... Stop the backup and raise error
	echo "Cannot get lock... Stop the backup, kill the pgsql connection and raise error...";
	logError error "Cannot get the lock on the Database server ${HOSTNAME}" ""
	exit 1
fi

###########################
####### RUN BACKUPS #######
###########################

echo "Lock acquired. Perform the SGBD dump and snapshots."

# BACKUP mode
if [[ "$BACKUP_MODE" == "backup" ]]; then
	
	db_backups "-backup"
 
	nas_snapshot "-backup"
 
	exit 0;
elif [[ "$BACKUP_MODE" == "cleanup" ]]; then
	# Delete all backup directories.
	find $BACKUP_DIR -maxdepth 1 -name "*-backup" -exec rm -rf '{}' ';'

	nas_cleanup_snapshot "-cleanup"

	exit 0;
fi

# MONTHLY BACKUPS
 
DAY_OF_MONTH=`date +%d`
 
if [ $DAY_OF_MONTH -eq 1 ];
then
	db_backups "-monthly"
 
#	# Delete all expired monthly directories. 10 is arbitrary, we just want to remove any backup older than the one we just made...
#	find $BACKUP_DIR -maxdepth 1 -mtime +10 -name "*-monthly" -exec rm -rf '{}' ';'
	# Delete all DB backup. The snapshot contains all the necessary backups...
	find $BACKUP_DIR -maxdepth 1 ( -name "*-monthly" -o -name "*-weekly" -o -name "*-daily" ) -exec rm -rf '{}' ';'
 
	nas_snapshot "-monthly"
 
	exit 0;
fi
 
# WEEKLY BACKUPS
 
DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`
 
if [ $DAY_OF_WEEK = $DAY_OF_WEEK_TO_KEEP ];
then
#	# Delete all expired weekly directories
#	# No need to use +$EXPIRED_DAYS, we only need the last backup, so +1
#	find $BACKUP_DIR -maxdepth 1 -mtime +1 -name "*-weekly" -exec rm -rf '{}' ';'
 	# Delete all DB backup. The snapshot contains all the necessary backups...
	find $BACKUP_DIR -maxdepth 1 ( -name "*-monthly" -o -name "*-weekly" -o -name "*-daily" ) -exec rm -rf '{}' ';'
 
	db_backups "-weekly"
 
	nas_snapshot "-weekly"
 
	exit 0;
fi
 
# DAILY BACKUPS
 
## Delete daily backups 7 days old or more
## No need to use +$((DAYS_TO_KEEP+1)), we only need the last backup, so +1
#find $BACKUP_DIR -maxdepth 1 -mtime +1 -name "*-daily" -exec rm -rf '{}' ';'
# Delete all DB backup. The snapshot contains all the necessary backups...
find $BACKUP_DIR -maxdepth 1 ( -name "*-monthly" -o -name "*-weekly" -o -name "*-daily" ) -exec rm -rf '{}' ';'
 
db_backups "-daily"

nas_snapshot "-daily"

###########################
##### RELEASE DB LOCK #####
###########################

exit 0