#!/bin/bash

if [[ "$HOME" == "" ]]; then
    HOME=$(cat /etc/passwd | grep -e "^zabbix" | cut -d: -f6)
fi

if [[ -e "$HOME/.pod" ]]; then
    NIRVA=$(cat $HOME/.pod | cut -d: -f1)
    NV_USER=$(cat $HOME/.pod | cut -d: -f2)
    NV_PWD=$(cat $HOME/.pod | cut -d: -f3)
fi
if [[ "$NIRVA" == "" ]]; then
    NIRVA=/home/nirva/bin/nirva
fi

if [[ "$NV_USER" == "" ]]; then
    NV_USER=nvadmin
fi
if [[ "$NV_PWD" == "" ]]; then
    NV_PWD=nirva
fi

export LD_LIBRARY_PATH=$NIRVA/Bin
NVCC=$NIRVA/Bin/nvcc

# Create the file for nvcc commands
NV_FILE_PATH=/tmp/nv_command_$$.txt

if [[ "$1" == "listeners" ]]; then
    cat <<EOF > $NV_FILE_PATH
; NIRVA active listeners count
; requires SYSTEM:LISTENER_LIST permission

NV_CMD="LISTENER:LIST"
NV_CMD="SYSTEM:OBJECT:GET" NAME="listener_list"
NV_CMD="LOCAL:OBJECT:TABLE_REMOVE_ROWS" NAME="listener_list" QUERY="STATUS=STOPPED"
NV_CMD="LOCAL:OBJECT:TABLE_GET_NUM_ROWS" NAME="listener_list"
nvcc::printdata 
EOF
elif [[ "$1" == "tasks" ]]; then
    cat <<EOF > $NV_FILE_PATH
; NIRVA active tasks count
; requires SYSTEM:SCHEDULER_LIST permission

NV_CMD="SCHEDULER:TASK_LIST"
NV_CMD="SYSTEM:OBJECT:GET" NAME="task_list"
NV_CMD="LOCAL:OBJECT:TABLE_REMOVE_ROWS" NAME="task_list" QUERY="ENABLE=NO"
NV_CMD="LOCAL:OBJECT:TABLE_GET_NUM_ROWS" NAME="task_list"
nvcc::printdata 
EOF
else
    # Unknown operation, return -1 and exit
    echo -n '-1'
    exit 0
fi

# Run the commands, and get results
RES=$($NVCC -p $2 -i $NV_FILE_PATH -u $NV_USER -w $NV_PWD)
ERR_CODE=$?

# Remove temp file, useless now
rm --force $NV_FILE_PATH

# Print the result
if [[ $ERR_CODE -eq "0" ]]; then
	echo -n $RES
else
	echo -n '0'
fi
