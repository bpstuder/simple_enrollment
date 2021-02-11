#!/bin/sh
###
# File: S-Simple-Enrollment.sh
# File Created: 2021-01-09 18:46:00
# Usage : Simple enrollment, based on DEPNotify launcher script.
# Author: Benoit-Pierre Studer
# -----
# HISTORY:
# 2021-02-04	Benoit-Pierre Studer	Added all the steps of previous DEPNotify based enrolment
###

CURRENT_USER=$(stat -f%Su /dev/console)
CURRENT_USERID=$(/usr/bin/id -u ${CURRENT_USER})

ENROLL_LOG="/var/log/enroll.log"

NOTIFICATION_APP="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"
JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# TESTING MODE
if [[ -z "${4}" ]]; then
  TESTING_MODE=true
else
  TESTING_MODE="${4}"
fi
echo "Testing mode : ${TESTING_MODE}" | tee -a ${ENROLL_LOG}

# WELCOME SETTINGS
if [[ -z "${5}" ]]; then
  WELCOME_POPUP=true
else
  WELCOME_POPUP="${5}"
fi
echo "Welcome popup enabled : ${WELCOME_POPUP}" | tee -a ${ENROLL_LOG}
WELCOME_TITLE="Welcome aboard"
WELCOME_TEXT="Thanks for choosing a Mac ! We want you to have a few applications and settings configured before you get started with your new Mac. 
This process should take 10 to 20 minutes to complete. 
If you need additional software or help, please visit the Store app in your Applications folder or on your Dock."

# Wait for user Finder
echo "Waiting for user session to open" | tee -a ${ENROLL_LOG}
while [[ -z $(pgrep -x "Finder") ]]; do
  sleep 1
done
echo "Session ready" | tee -a ${ENROLL_LOG}

echo "Current user is : ${CURRENT_USER}"
try=0
until [[ ${CURRENT_USER} != "_mbsetupuser" ]] || [[ "$try" -gt "20" ]]; do
  ((try++))
  echo "Waiting 5s for user session to open. (Try : $try/20)" | tee -a ${ENROLL_LOG}
  sleep 5
  CURRENT_USER=$(stat -f%Su /dev/console)
  echo "Current user is : ${CURRENT_USER}" | tee -a ${ENROLL_LOG}
  if [[ $try == 20 ]]; then
    echo "[ERROR] Session user is still _mbpsetupuser. Exiting..." | tee -a ${ENROLL_LOG}
    exit 1
  fi
done

echo "Sleep 10s to finish session opening" | tee -a ${ENROLL_LOG}
sleep 10

# Self Service Settings
# SELF_SERVICE_APP_NAME="Self Service.app"
# SELF_SERVICE_NAME="$(echo "$SELF_SERVICE_APP_NAME" | cut -d "." -f1)"
# echo "Opening ${SELF_SERVICE_APP_NAME} for assets download." | tee -a ${ENROLL_LOG}
# open -a "/Applications/${SELF_SERVICE_APP_NAME}" --hide

# try=0
# SELF_SERVICE_PID=$(pgrep -l "Self Service" | cut -d " " -f1)
# until [[ ! -z "$SELF_SERVICE_PID" ]] || [[ "$try" -gt "20" ]]; do
#   ((try++))
#   echo "Waiting for ${SELF_SERVICE_NAME}. (Try : $try/20)" | tee -a ${ENROLL_LOG}
#   sleep 10

#   SELF_SERVICE_PID=$(pgrep -l "Self Service" | cut -d " " -f1)
#   echo "PID : $SELF_SERVICE_PID" | tee -a ${ENROLL_LOG}
#   if [[ $try == 20 ]]; then
#     echo "[ERROR] Unable to open ${SELF_SERVICE_NAME}" | tee -a ${ENROLL_LOG}
#     exit 1
#   fi
# done

# # Loop waiting on the branding image to properly show in the users library
# try=0
# CUSTOM_BRANDING_PNG="/Users/$CURRENT_USER/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
# until [[ -f "$CUSTOM_BRANDING_PNG" ]] || [[ "$try" -gt "20" ]]; do
#   ((try++))
#   echo "Waiting for branding image from Jamf Pro. (Try : $try/20)" | tee -a ${ENROLL_LOG}
#   sleep 10
#   if [[ $try == 20 ]]; then
#     echo "[ERROR] Unable to get the Self Service Branding image." | tee -a ${ENROLL_LOG}
#     exit 1
#   fi
# done

# # Closing Self Service
# SELF_SERVICE_PID=$(pgrep -l ${SELF_SERVICE_NAME} | cut -d " " -f1)
# echo "Killing Self Service PID $SELF_SERVICE_PID." | tee -a ${ENROLL_LOG}
# kill "$SELF_SERVICE_PID"

# ENROLLMENT COMPLETE SETTINGS
ENROLL_COMPLETE_TITLE="Enrollment complete"
ENROLL_COMPLETE_TEXT="Enrollment is now complete. Click on Logout to finish."

# SOFTWARE POLICIES

SOFTWARE_ARRAY=(
  # "Installing Rosetta2,enroll_rosetta"
  "Installing Office 365,enroll_office365"
  "Installing Firefox,enroll_firefox"
  "Installing NoMAD,enroll_nomad"
)
SOFTWARE_COUNT=${#SOFTWARE_ARRAY[@]}

# CUSTOMIZATION POLICIES

CUSTOMIZATION_ARRAY=(
  "Enabling FileVault,enroll_filevault"
  "Setting Computer Name, enroll_set-computername "
)
CUSTOMIZATION_COUNT=${#CUSTOMIZATION_ARRAY[@]}

###############################################################################
# MAIN SCRIPT
###############################################################################

echo "Starting post enrollment tasks" | tee -a ${ENROLL_LOG}

if [[ "$WELCOME_POPUP" == true ]]; then
  echo "Displaying Welcome popup" | tee -a ${ENROLL_LOG}
  "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" \
    -windowType hud \
    -windowPosition lr \
    -title "${WELCOME_TITLE}" \
    -description "${WELCOME_TEXT}" \
    -alignDescription natural \
    -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarCustomizeIcon.icns \
    -button1 OK \
    -defaultButton 0 \
    -lockHUD &
fi

echo "Sleeping 10s before starting enrollment" | tee -a ${ENROLL_LOG}
sleep 10

echo "${SOFTWARE_COUNT} softwares to install" | tee -a ${ENROLL_LOG}
launchctl asuser "$CURRENT_USERID" "$NOTIFICATION_APP" \
  -message "Installing softwares" \
  -title "Enrollment in progress..."

for POLICY in "${SOFTWARE_ARRAY[@]}"; do
  POLICY_TEXT=$(echo "$POLICY" | cut -d ',' -f1)
  POLICY_NAME=$(echo "$POLICY" | cut -d ',' -f2)

  echo "Processing: ${POLICY_TEXT}" | tee -a ${ENROLL_LOG}
  if [ "$TESTING_MODE" = true ]; then
    sleep 10
  elif [ "$TESTING_MODE" = false ]; then
    /usr/local/bin/jamf policy -event "${POLICY_NAME}"
  fi
done

echo "${CUSTOMIZATION_COUNT} customization policies to install" | tee -a ${ENROLL_LOG}
launchctl asuser "$CURRENT_USERID" "$NOTIFICATION_APP" \
  -message "Customizing your experience" \
  -title "Enrollment in progress..."

for POLICY in "${CUSTOMIZATION_ARRAY[@]}"; do
  POLICY_TEXT=$(echo "$POLICY" | cut -d ',' -f1)
  POLICY_NAME=$(echo "$POLICY" | cut -d ',' -f2)

  echo "Processing: ${POLICY_TEXT}" | tee -a ${ENROLL_LOG}
  if [ "$TESTING_MODE" = true ]; then
    sleep 10
  elif [ "$TESTING_MODE" = false ]; then
    /usr/local/bin/jamf policy -event "${POLICY_NAME}"
  fi
done

launchctl asuser "$CURRENT_USERID" "$NOTIFICATION_APP" \
  -message "All tasks completed successfully" \
  -title "Enrollment complete"

echo "Checking FileVault status" | tee -a ${ENROLL_LOG}
FV_DEFERRED=$(/usr/bin/fdesetup status | grep "Deferred" | cut -d ' ' -f6)
echo "Filevault deferred status is : ${FV_DEFERRED}" | tee -a ${ENROLL_LOG}

echo "Enrollment complete" | tee -a ${ENROLL_LOG}
if [ "$TESTING_MODE" = true ]; then
  sleep 10
elif [ "$TESTING_MODE" = false ]; then
  if [[ "${FV_DEFERRED}" == "active" ]]; then
    "${JAMF_HELPER}" \
      -windowType utility \
      -title "${ENROLL_COMPLETE_TITLE}" \
      -description "${ENROLL_COMPLETE_TEXT}" \
      -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns" \
      -button1 "Logout"
    pkill loginwindow
  else
    "${JAMF_HELPER}" \
      -windowType utility \
      -title "${ENROLL_COMPLETE_TITLE}" \
      -description "${ENROLL_COMPLETE_TEXT}" \
      -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns" \
      -button1 "Let's start"
  fi
fi

exit 0
