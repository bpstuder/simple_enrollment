#!/bin/zsh
###
# File: Simple-Enrollment-v2.sh
# File Created: 2022-03-14 12:19:37
# Usage :
# Author: Benoit-Pierre STUDER
# -----
# HISTORY:
# 2023-01-16	Benoit-Pierre STUDER	Added power check + Caffeinate
# 2022-10-04	Benoit-Pierre STUDER	Updated fullscreen message. Modified openSSL decryption to work on macOS 13.
# 2022-04-26	Benoit-Pierre STUDER	Added Fullscreen management
# 2022-03-18	Benoit-Pierre STUDER	Authentication is now with Bearer Token. Made the policies dynamic based on Category
###

jamfProUser="$4"
jamfProPassEnc="$5"
jamfProSalt="$6"
jamfProPassPhrase="$7"
testingMode="$8"  #true of false
welcomePopup="$9" #true of false
fullScreen="$10" #true of false

jamfCategory="_Enrollment-Policies"

# Duration in second to plug AC adapter
powerCheckWait=30 

jamfProPass=$(echo "$jamfProPassEnc" | /usr/bin/openssl enc -aes256 -md md5 -d -a -A -S "$jamfProSalt" -k "$jamfProPassPhrase")

jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url)
jamfProURL=${jamfProURL%%/}

echo "Connecting to $jamfProURL"
# created base64-encoded credentials
encodedCredentials=$(printf "${jamfProUser}:${jamfProPass}" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i -)
# generate an auth token
authToken=$(/usr/bin/curl "$jamfProURL/api/auth/tokens" \
  --silent \
  --request POST \
  --header "Authorization: Basic $encodedCredentials" \
  --header "Content-Length: 0" \
  -w "\n%{http_code}")

httpCode=$(tail -n1 <<<"${authToken}")
httpBody=$(sed '$ d' <<<"${authToken}")

echo "Command HTTP result : ${httpCode}"
# echo "Response : ${httpBody}"

if [[ ${httpCode} == 200 ]]; then
  echo "Token creation done"
else
  echo "[ERROR] Unable to create token. Curl code received : ${httpCode}"
  exit 1
fi

# parse authToken for token, omit expiration
token=$(awk -F \" '{ print $4 }' <<<"$authToken" | xargs)
#######

logFile="/var/log/enroll.log"

currentUser=$(stat -f%Su /dev/console)
currentUserID=$(/usr/bin/id -u ${CURRENT_USER})
currentSystemVersion=$(sw_vers -productVersion)
hostSerialNumber=$(system_profiler SPHardwareDataType | grep "Serial Number" | awk -F ": " '{print $2}')
jamfHelperExe="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
notificationApp="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"

# VARIABLES
############

# TESTING MODE
if [[ -z $testingMode ]]; then
  testingMode=true
fi
echo "Testing mode : ${testingMode}" | tee -a ${logFile}

# WELCOME SETTINGS
if [[ -z $welcomePopup ]]; then
  welcomePopup=true
fi
echo "Welcome popup enabled : ${welcomePopup}" | tee -a ${logFile}
welcomeTitle="Welcome aboard"
welcomeText="Thanks for choosing a Mac ! We want you to have a few applications and settings configured before you get started with your new Mac. 
This process should take 10 to 20 minutes to complete. 
If you need additional software or help, please visit the Store app in your Applications folder or on your Dock."

# FULLSCREEN SETTINGS
if [[ -z fullScreen ]]; then
  fullScreen=true
fi
echo "Fullscreen enabled : ${fullScreen}" | tee -a ${ENROLL_LOG}
fullScreenTitle="Welcome aboard"
fullScreenHeading="Enrollment in progress"
fullScreenText="We are preparing your computer and it should take around 20 minutes. It's time for a coffee break !"

# ENROLLMENT COMPLETE SETTINGS
enrollCompleteTitle="Enrollment complete"
enrollCompleteText="Enrollment is now complete. Click on Logout to finish."

# MAIN SCRIPT
##############

# Check if enrollment has already been done
if [[ -f /private/var/db/.EnrollmentDone ]]; then
  echo "Enrollment already done. Exiting..." | tee -a ${logFile}
  exit 0
fi

# Collecting Policies to run

categoryPoliciesResult=$(/usr/bin/curl "${jamfProURL}/JSSResource/policies/category/${jamfCategory}" \
  --silent \
  --insecure \
  --request GET \
  --header "Authorization: Bearer $token" \
  --header "Accept: application/xml" \
  -w "\n%{http_code}")

httpCode=$(tail -n1 <<<"${categoryPoliciesResult}")
httpBody=$(sed '$ d' <<<"${categoryPoliciesResult}")

# echo "Response : ${httpBody}"

if [[ ${httpCode} == 200 ]]; then
  echo "Policies for category $jamfCategory retrieved" | tee -a ${logFile}
else
  echo "[ERROR] Unable to collect policies for category $jamfCategory. Curl code received : ${httpCode}" | tee -a ${logFile}
  exit 1
fi

policiesCount=$(echo $httpBody | xmllint --xpath '//policies/size/text()' -)
echo "Found $policiesCount policies to proceed" | tee -a ${logFile}
declare -A policiesToRun

for ((i = 1; i <= $policiesCount; i++)); do
  policyID="$(echo $httpBody | xmllint --xpath '//policies/policy['"$i"']/id/text()' -)"
  policyName="$(echo $httpBody | xmllint --xpath '//policies/policy['"$i"']/name/text()' -)"
  # policiesToRun[$policyID]=$policyName
  policiesToRun[$policyName]=$policyID
done

# for policy in "${(kn)policiesToRun[@]}"; do

#   echo "Policy ${policiesToRun[$policy]} : ${policy}"
# done

# Wait for user Finder
echo "Waiting for user session to open" | tee -a ${logFile}
while [[ -z $(pgrep -x "Finder") ]]; do
  sleep 1
done
echo "Session ready" | tee -a ${logFile}

echo "Current user is : ${currentUser}"
try=0
until [[ ${currentUser} != "_mbsetupuser" ]] || [[ "$try" -gt "20" ]]; do
  ((try++))
  echo "Waiting 5s for user session to open. (Try : $try/20)" | tee -a ${logFile}
  sleep 5
  currentUser=$(stat -f%Su /dev/console)
  echo "Current user is : ${currentUser}" | tee -a ${logFile}
  if [[ $try == 20 ]]; then
    echo "[ERROR] Session user is still _mbpsetupuser. Exiting..." | tee -a ${logFile}
    exit 1
  fi
done

echo "Sleep 10s to finish session opening" | tee -a ${logFile}
sleep 10

echo "Checking user has plugged his computer to AC"

if [[ ! $(pmset -g ps | head -1) =~ "AC Power" ]]; then
  echo "No AC power detected" | tee -a ${logFile}
  echo "Waiting for AC power..." | tee -a ${logFile}
  "${jamfHelperExe}" \
      -windowType utility \
      -title "Warning" \
      -description "Please ensure your laptop is connected to AC power to avoid unexpected shutdown during enrollment." \
      -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns" \
      -heading "AC Power not detected" &
  jamfHelperPowerPID=$!
  while [[ "$powerCheckWait" -gt "0" && ! $(pmset -g ps | head -1) =~ "AC Power" ]]; do
    sleep 1
    ((powerCheckWait--))
    echo "Time left : ${powerCheckWait}s"
  done
  if [[ $powerCheckWait == "0" ]]; then
    kill "$jamfHelperPowerPID"
    "${jamfHelperExe}" \
        -windowType utility \
        -title "Error" \
        -description "No AC Power detected. Please plug it in and relaunch Enrollment." \
        -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns" \
        -heading "AC Power not detected" \
        -button1 OK \
        -defaultButton 0 &
    echo "[ERROR] No AC Power Detected" | tee -a ${logFile}
    exit 1
  fi
  if [[ $(pmset -g ps | head -1) =~ "AC Power" ]] ; then
    echo "AC Power Detected. Continuing" | tee -a ${logFile}
    kill "$jamfHelperPowerPID"
  fi
fi

echo "Caffeinating the mac"
caffeinate -dis &
caffeinatePID=$!

echo "Starting post enrollment tasks" | tee -a ${logFile}

if [[ "$welcomePopup" == true ]]; then
  echo "Displaying Welcome popup" | tee -a ${logFile}
  "${jamfHelperExe}" \
    -windowType hud \
    -windowPosition lr \
    -title "${welcomeTitle}" \
    -description "${welcomeText}" \
    -alignDescription natural \
    -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarCustomizeIcon.icns \
    -button1 OK \
    -defaultButton 0 \
    -lockHUD &
fi

if [[ "$fullScreen" == true ]]; then
  echo "Displaying Fullscreen message" | tee -a ${ENROLL_LOG}
  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
    -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarCustomizeIcon.icns" \
    -description ${fullScreenText} \
    -windowType fs \
    -heading ${fullScreenHeading} \
    &
fi

echo "${policiesCount} policies to run" | tee -a ${logFile}
launchctl asuser "$currentUserID" "$notificationApp" \
  -message "Installing softwares" \
  -title "Enrollment in progress..."

for policy in "${(kn)policiesToRun[@]}"; do
  echo "Processing Policy ${policiesToRun[$policy]} : ${policy}" | tee -a ${logFile}
  if [ "$testingMode" = true ]; then
    sleep 10
  elif [ "$testingMode" = false ]; then
    /usr/local/bin/jamf policy -id "${policiesToRun[$policy]}"
  fi
done

launchctl asuser "$currentUserID" "$notificationApp" \
  -message "All tasks completed successfully" \
  -title "Enrollment complete"

echo "Checking FileVault status" | tee -a ${logFile}
fileVaultDeferred=$(/usr/bin/fdesetup status | grep "Deferred" | cut -d ' ' -f6)
echo "Filevault deferred status is : ${fileVaultDeferred}" | tee -a ${logFile}

echo "Enrollment complete" | tee -a ${logFile}
if [ "$testingMode" = true ]; then
  sleep 10
  pkill $caffeinatePID
elif [ "$testingMode" = false ]; then
  pkill jamfHelper
  pkill $caffeinatePID
  if [[ "${fileVaultDeferred}" == "active" ]]; then
    "${jamfHelperExe}" \
      -windowType utility \
      -title "${enrollCompleteTitle}" \
      -description "${enrollCompleteText}" \
      -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns" \
      -button1 "Logout"
    pkill loginwindow
  else
    "${jamfHelperExe}" \
      -windowType utility \
      -title "${enrollCompleteTitle}" \
      -description "${enrollCompleteText}" \
      -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns" \
      -button1 "Let's start"
  fi
fi

# Create file to prevent re-enrollment
touch /private/var/db/.EnrollmentDone

# expire the auth token
echo "Expiring Token"
result=$(/usr/bin/curl "$jamfProURL/api/auth/invalidateToken" \
    --silent \
    --request POST \
    --header "Authorization: Bearer $token" \
    --header "Content-Length: 0" \
    -w "\n%{http_code}")
httpCode=$(tail -n1 <<<"${result}")

if [[ ${httpCode} == 204 ]]; then
    echo "Command HTTP result : ${httpCode}"
    echo ">> Done"
else
    echo "[ERROR] Unable to expire token. Curl code received : ${httpCode}"
fi

exit 0