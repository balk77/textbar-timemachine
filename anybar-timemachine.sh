#!/usr/bin/env zsh -f
# Purpose: show Time Machine current status in AnyBar
# Based on https://github.com/tjluoma/textbar-timemachine from:	Timothy J. Luoma
# Modified by S. Balkenende

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.



## Note:	This has been tested with 1 remote Time Machine drive.
##			Not sure how it would work if there are multiple of either of those

NAME="$0:t:r"

## Define sub directory under $HOME, should end with a /
# for instance "Documents/timemachine/"
SUBDIR="Documents/timemachine/"


## Check if last run is too old
## Default = one day: 24 * 60 * 60 seconds:
TM_AGE=$((24*60*60))
TM_AGE=1

## MQTT publication command if error
# 0=clear, 1=error
MQTT_COMMAND="/opt/homebrew/bin/mqtt pub -h 192.168.0.9 -t macbook/timemachine/error -m "
# set to MQTT_COMMAND="" when not required

## AnyBar colors
ANYBAR_COPYING="green"
ANYBAR_IDLE="hollow"
ANYBAR_ERROR="exclamation"

## AnyBar parameters
ANYBAR_HOST="localhost"
ANYBAR_PORT="1738"
# find number of running AnyBar processes
ANYBAR_PROC=$(ps aux | grep -v grep | grep -ci anybar)

if [ -e "$HOME/.path" ]
then
	source "$HOME/.path"
else
	PATH=/usr/local/scripts:/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin:$PWD:$HOME/$SUBDIR
fi


zmodload zsh/datetime

DATE=$(strftime "%Y-%m-%d" "$EPOCHSECONDS")

TIME=$(strftime "%Y-%m-%d--%H.%M.%S" "$EPOCHSECONDS")

function timestamp { strftime "%Y-%m-%d--%H.%M.%S" "$EPOCHSECONDS" }

if [[ "$NETWORK" == "" ]]
then
	TIME_CAPSULE_MNTPNT=""
else
	TIME_CAPSULE_MNTPNT="$NETWORK"
fi

	# If there is a local Time Machine mounted, this will show the mount point.
LOCAL=$(tmutil destinationinfo | grep 'Mount Point'      | awk -F'/' '/Volumes/{print $NF}')

if [[ "$LOCAL" == "" ]]
then
	TIME_MACHINE_MNTPNT="x"
else
	TIME_MACHINE_MNTPNT="/Volumes/$LOCAL"
fi



####### The 'PREVIOUS_DESTINATION_FILE' file should have two lines, like so:
# 7618460C-3E5B-4829-BB24-37F9F0F23824
# /Volumes/Time Machine Backups
PREVIOUS_DESTINATION_FILE="$HOME/$SUBDIR.$NAME.previous-destination.txt"

# first line of the file
PREVIOUS_DESTINATION_ID=$(head -1 "$PREVIOUS_DESTINATION_FILE")

# last line of the file
PREVIOUS_DESTINATION_NAME=$(tail -1 "$PREVIOUS_DESTINATION_FILE")

# both combined for easier reference
PREVIOUS_DESTINATION="$PREVIOUS_DESTINATION_NAME"

# save the phase that we found 'last time' so we can compare them
PREVIOUS_PHASE_FILE="$HOME/$SUBDIR.${NAME}.previous-phase.txt"

# this will have the actual name of the previous phase
PREVIOUS_PHASE=$(head -1 "$PREVIOUS_PHASE_FILE")

# this is used to track when Time Machine last ran, so I can tell how long it has been since it ran
LAST_RUN_LOG="$HOME/$SUBDIR.$NAME.lastrun.txt"

# this shows the current phase in one CamelCaseWord
PHASE=$(tmutil currentphase)

## Start AnyBar if not running
echo $ANYBAR_PROC "process"
if [[ $ANYBAR_PROC==0 ]]
then
	echo "Starting AnyBar"
	open -a AnyBar
fi

# ## if phase is not "Copying" and previous run is too old:
# # issue an error
# if [[ "$PHASE" != "Copying" ]]
# then
# 	LAST_RUN_TIME=$(head -1 "$LAST_RUN_LOG" 2>/dev/null || echo '0')
# 	LAST_RUN_TIME=$(head -1 "$LAST_RUN_LOG" )
# 	## Check if last run is too old
# 	## Default = one day: 24 * 60 * 60 seconds: 

# 	if [[ $(($EPOCHSECONDS-$LAST_RUN_TIME)) > $TM_AGE ]]
# 	then
# 		echo "Successful TimeMachine run is too old"
# 		echo -n $ANYBAR_ERROR | nc -4u -w0 $ANYBAR_HOST $ANYBAR_PORT
# 		echo $(MQTT_COMMAND 1)
# 		exit 0
	
# 	fi
# fi



if [[ "$PHASE" != "$PREVIOUS_PHASE" ]]
then

	if [[ "$PHASE" == "BackupNotRunning" ]]
	then

		echo "Time Machine has finished"

		if (( $+commands[when-timemachine-finishes.sh] ))
		then
				# This script has commands that I might want to run when Time Machine finishes,
				# such as shutting down my Mac or just ejecting the Time Machine drive(s)
				#
				# I like having this in a separate file so I can make changes without
				# having to change this script
			when-timemachine-finishes.sh

		fi

		# If you want to run commands when Time Machine has finished,
		# you can add them here:
		
		echo -n $ANYBAR_IDLE | nc -4u -w0 $ANYBAR_HOST $ANYBAR_PORT
		## Reset the MQTT error topic
		MQTT_ERROR=0
		



	elif [[ "$PREVIOUS_PHASE" == "BackupNotRunning" ]]
	then

		echo "Time Machine has started"
		## Reset the MQTT error topic
		MQTT_ERROR=0
	else
		MQTT_ERROR=0
	fi

		# lastly, update the 'PREVIOUS_PHASE_FILE'
	echo "$PHASE" > "$PREVIOUS_PHASE_FILE"
fi

if [[ "$PHASE" == "BackupNotRunning" ]]
then
		# if we get here, there is no active backup running,

	if [[ -e "$LAST_RUN_LOG" ]]
	then
			# get the first line of the file
		LAST_RUN_TIME=$(head -1 "$LAST_RUN_LOG" 2>/dev/null || echo '0')

			# convert the "last run" time to get a date in YYYY/MM/DD format
		LAST_RUN_TIME_READABLE_DATE=$(strftime "%Y/%m/%d" "$LAST_RUN_TIME")

		# get the "current time" in a YYYY/MM/DD format
		CURRENT_TIME_READABLE_DATE=$(strftime "%Y/%m/%d" "$LAST_RUN_TIME")

		# get the time in 12 hour format with hour and minute
		LAST_RUN_TIME_READABLE_TIME=$(strftime "%-l:%M %p" "$LAST_RUN_TIME")

		# see if the date is today's date or previous date
		if [[ "$CURRENT_TIME_READABLE_DATE" == "$LAST_RUN_TIME_READABLE_DATE" ]]
		then
				LAST_RUN_TIME_READABLE="Today at $LAST_RUN_TIME_READABLE_TIME"
		else
				LAST_RUN_TIME_READABLE="$LAST_RUN_TIME_READABLE_TIME on $LAST_RUN_TIME_READABLE_DATE"
		fi

			# compare the time right now vs the time of the last run
		DIFF=$(($EPOCHSECONDS - $LAST_RUN_TIME))

			# convert the seconds to a readable format
		DIFF_READABLE=$(seconds2readable.sh "$DIFF")

			# Here is where you set the time elapsed before you get warned with a special status line
			## Default = one day: 24 * 60 * 60 seconds: 

	
		if [ "$DIFF" -ge $TM_AGE ]
		then

				# The '⚠️' will go on the menu bar, then there is a newline for the rest of the message
			echo "⚠️\nTime Machine has not run in\n${DIFF_READABLE}\n----\nLast Run: ${LAST_RUN_TIME_READABLE}\nLast Backup To:\n${PREVIOUS_DESTINATION}"
			echo -n $ANYBAR_ERROR | nc -4u -w0 $ANYBAR_HOST $ANYBAR_PORT
			MQTT_ERROR=1

		else
			## Newline keeps it off menu bar
			echo "\nLast backup to '${PREVIOUS_DESTINATION}'\n${LAST_RUN_TIME_READABLE} (${DIFF_READABLE} ago)"
			## Reset the MQTT error topic
			MQTT_ERROR=0

		fi

	else
			# if there isn't a LAST_RUN_LOG then create one now

		echo "$EPOCHSECONDS" >| "$LAST_RUN_LOG"

		echo "\nJust finished"
		## Reset the MQTT error topic
		MQTT_ERROR=0

	fi

		# this will create a horizontal line in TextBar's dropdown menu

	echo '----'

		# show if the Time Capsule drive is mounted
	if ( mount | fgrep -q "/${TIME_CAPSULE_MNTPNT} on " )
	then
		echo "Remote Destination Mounted"
	else
		echo "Remote Destination NOT Mounted"
	fi

		# show if the local Time Machine drive is mounted
	if [[ -d "$TIME_MACHINE_MNTPNT" ]]
	then
		echo "Local Destination Mounted"
	else
		echo "Local Destination NOT Mounted"
	fi

	exit 0
fi

# file where we store the entire output of the 'tmutil status' information
CURRENT_STATUS="$HOME/$SUBDIR.$NAME.status.txt"

( tmutil status 2>&1 ) >| "$CURRENT_STATUS"

	# Now we parse the local file for the info we want.
BYTES=$(sed 's#^ *##g ; s#\;##g; s#"##g' "$CURRENT_STATUS" | awk -F' ' '/^bytes/{print $NF}' || echo 0)
	SIZE_COPIED=$(bytes2readable.sh "$BYTES" | sed 's#\.[0-9][0-9] MB# MB#g')

TOTAL_BYTES=$(sed 's#^ *##g ; s#\;##g; s#"##g' "$CURRENT_STATUS" | awk -F' ' '/^totalBytes/{print $NF}' || echo 0)
	TOTAL_TO_COPY=$(bytes2readable.sh "$TOTAL_BYTES" | sed 's#\.[0-9][0-9] MB# MB#g')

	# now we calculate the byte info
if [ "$TOTAL_BYTES" != "" -a "$BYTES" != "" ]
then

	PERCENT_OF_BYTES=$(echo "scale=2 ; ($BYTES / $TOTAL_BYTES)" | bc | sed 's#\.##g ; s#$#%#g' || echo 0)

	BYTES_REMAINING=$(($TOTAL_BYTES - $BYTES))
		BYTES_REMAINING_READABLE=$(bytes2readable.sh "$BYTES_REMAINING" | sed 's#\.[0-9][0-9] MB# MB#g')

else

	PERCENT_OF_BYTES=""
	BYTES_REMAINING=""
	BYTES_REMAINING_READABLE=""

fi

	# get the current files count
JUST_FILES=$(sed 's#^ *##g ; s#\;##g; s#"##g' "$CURRENT_STATUS" | awk -F' ' '/^files/{print $NF}')

	# get the total files count
TOTAL_FILES=$(sed 's#^ *##g ; s#\;##g; s#"##g' "$CURRENT_STATUS" | awk -F' ' '/^totalFiles/{print $NF}')

	# change the number to have commas in the right places
if [[ "$JUST_FILES" == "$TOTAL_FILES" ]]
then
	FILES_SO_FAR_READABLE=$(commaformat.sh "$JUST_FILES")
else

	JUST_FILES_READABLE=$(commaformat.sh "$JUST_FILES")
	TOTAL_FILES_READABLE=$(commaformat.sh "$TOTAL_FILES")

	FILES_SO_FAR_READABLE="$JUST_FILES_READABLE / $TOTAL_FILES_READABLE"
fi

	# sometimes this just doesn't exist
TIME_REMAINING=$(sed 's#^ *##g ; s#\;##g; s#"##g' "$CURRENT_STATUS" | awk -F' ' '/^TimeRemaining/{print $NF}')

	# get the ID of the current destination
DESTINATION_ID=$(awk -F'"' '/DestinationID/{print $2}' "$CURRENT_STATUS" )

	# get the mount point
DESTINATION_NAME=$(awk -F'"' '/DestinationMountPoint/{print $2}' "$CURRENT_STATUS" )

[[ "$DESTINATION_NAME" == "" ]] \
&& DESTINATION_NAME=$(tmutil destinationinfo \
| fgrep -B1 "$DESTINATION_ID" \
| egrep '^Mount Point '  \
| sed 's#^Mount Point   : ##g' \
| sed 's#/Volumes/##' \
| sed 's#.timemachine/##' \
| sed 's#._afpovertcp.*##')

	# if the destination ID is not blank, save it and the name to the file
if [[ "$DESTINATION_ID" != "" ]]
then
	echo "${DESTINATION_ID}\n${DESTINATION_NAME}" >| "$PREVIOUS_DESTINATION_FILE"
fi

	# sometimes the time remaining doesn't exist so we can't use it
if [[ "$TIME_REMAINING" == "" ]]
then

	READABLE_TIME='(Time Unavailable)'

	ETA=''

else
		# convert the time remaining to a readable format
	READABLE_TIME=$(seconds2readable.sh "$TIME_REMAINING")

		# calculate when the completed time will be when it finishes
		# note that this estimate is often completely wrong, so
		# don't rely on it for anything
	let ADJUSTED_TIME=EPOCHSECONDS+TIME_REMAINING

		# -l means "hour without leading zero OR leading space"
	# ETA=$(strftime "%Y-%m-%d at %-l:%M:%S %p" "$ADJUSTED_TIME")

		# show the time in 12 hour format + minute + am/pm
	ETA=$(strftime "%-l:%M %p" "$ADJUSTED_TIME")
fi

if [[ "$PHASE" == "Copying" ]]
then
		# this is where we are most of the time when running
	echo " $PERCENT_OF_BYTES $DESTINATION_NAME"
	# rm -f "$LAST_RUN_LOG"
	echo -n $ANYBAR_COPYING | nc -4u -w0 $ANYBAR_HOST $ANYBAR_PORT
	MQTT_ERROR=0
	

else
		# if we get here, we are not copying
	echo " $PHASE"
	echo -n $ANYBAR_IDLE | nc -4u -w0 $ANYBAR_HOST $ANYBAR_PORT
	# rm -f "$LAST_RUN_LOG"
	MQTT_ERROR=0
fi

## This is already in menu bar so we don't need to include it in the drop-down
# Percent: $PERCENT_OF_BYTES

## here is where we output all the info in the format we want

echo "Phase: $PHASE

Destination: $DESTINATION_NAME
----
Total: $TOTAL_TO_COPY ($FILES_SO_FAR_READABLE files)
	Copied: $SIZE_COPIED
	Remain: $BYTES_REMAINING_READABLE
----
Time Remaining: $READABLE_TIME
ETA: $ETA
----"

## Now we just include the entire output of 'tmutil status' just so we can see it.

cat "$CURRENT_STATUS"

if [[ -z "$MQTT_COMMAND" ]]
then
	echo "MQTT not requested"
else
	echo "issue MQTT topic"
	eval "${MQTT_COMMAND} ${MQTT_ERROR}"
	
fi

exit 0
