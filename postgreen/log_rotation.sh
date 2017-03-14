#!/bin/bash

# Log rotate
LOG_FILE="$1"
LOG_DIR=$(cd ${LOG_FILE%/*} && pwd -P)
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
