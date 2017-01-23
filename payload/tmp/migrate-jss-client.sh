#!/bin/bash

###############################################################################
# configuration                                                               #
###############################################################################

# JSS URLs
old_jss_url="https://old.jss.url"
new_jss_url="https://new.jss.url"

# Run mode
# 'silent' = for automated migrations; does not invoke a UI
# 'interactive' = for Self Service policies; invokes a UI for user alerts
# NOTE: Specify the DEFAULT value – parameter 4 can be passed in by the JSS
#       for greater flexibility in deployment, i.e.:
#           runmode="${4:-silent}" or "runmode=${4:-interactive}"
runmode="${4:-interactive}"

# MDM profile UID
# The default value here should be correct, but always check your environment!
# Used if the jamf binary is unable to remove the profile and we need to attempt
# removal using the profiles binary
mdm_uid="00000000-0000-0000-A000-4A414D460003"

# Log file path
log_file_path="/var/log/$(date "+%Y-%m-%d")-jss-client-migration.log"

# UI
# Window title heading used for all UI windows
window_title="Self Service Upgrade"
# Icon used in UI windows
icon="/Applications/Self Service.app/Contents/Resources/Self Service.icns"
# UI heading (bolded top line) for alert shown prior to migration during
# interactive/Self Service use of this script
heading_pre="Self Service will now be upgraded."
# UI heading (bolded top line) for alert shown after completion of migration
# during interactive/Self Service use of this script
heading_post="Self Service upgrade complete."
# UI main body message show before migration
body_pre="Self Service will automatically close to complete the ugprade. This should take about 5 minutes. Please do not open Self Service until you receive a notification that the ugprade is complete."
# UI main body for message shown after migration
body_post="Self Service has been successfully upgraded. You may now re-open Self Service to access software installations and maintenance utilities. Please contact ITS if you need additional assistance."

# locate jamf binary
jamf=$(which jamf)
# specify path to jamfHelper
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# file logging
flog(){
    echo "$(date "+%Y-%m-%d %H:%M:%S") ${1}" | tee -a "${log_file_path}"
}

###############################################################################
# main program                                                                #
###############################################################################

flog "🎉 Beginning JSS migration"

# Make sure we're actually connected to the old JSS
if echo "$(${jamf} checkJSSConnection)" | grep -q "${old_jss_url}"; then
    flog "...still connected to the old JSS ${old_jss_url}"
fi

if [[ "${runmode}" == "interactive" ]]; then
    "${jamfHelper}" -windowType utility -title "${window_title}" -heading "${heading_pre}" -description "${body_pre}" -button1 "Ok" -icon "${icon}"
    flog "...alerted user"
fi
# wait 5 seconds for  good measure
sleep 5

# close self service if running
ss_pid=$(pgrep "Self Service")
if [[ $ss_pid ]]; then
    flog "Self Service is running"
    osascript -e "tell application \"Self Service\" to quit"
    flog "...Closed Self Service"
fi

# remove the mdm profile
flog "Attempting to remove MDM profile"
"${jamf}" removeMdmProfile
if [[ $? -gt 0 ]]; then
    flog "...unable to remove MDM profile via jamf binary"
    flog "...attempting to remove MDM profile by force"
    profiles -R -p "${mdm_uid}"
    if [[ $? -gt 0 ]]; then
        flog "...unable to remove MDM profile by force"
        flog "☠️☠️☠️ this device may not be properly managed on the new JSS ☠️☠️☠️"
    else
        flog "...successfully removed the MDM profile by force"
    fi
else
    flog "...successfully removed the MDM profile"
fi

# remove the current jamf framework
flog "Removing JAMF framework"
"${jamf}" removeFramework
flog "Removed the JAMF framework"

# run the new quickadd
flog "Installing new quickadd"
/usr/sbin/installer -dumplog -verbose -pkg /Library/Application\ Support/QuickAdd-jamfcloud.pkg -target "/"
flog "Finished installing new quickadd"

# delete the quickadd
rm /Library/Application\ Support/QuickAdd-jamfcloud.pkg
flog "Removed QuickAdd package"

# sleep again
sleep 10

# manage and enable mdm
flog "Managing machine"
"${jamf}" manage
flog "Enabling MDM"
"${jamf}" mdm

# stop, unload, remove launchdaemon
flog "Removing launchd job"
# TODO: variabalize and remove file
flog "Removed launchd job"

flog "Managing machine again"
"${jamf}" manage

sleep 20


flog "Re-opening Self Service"
"${jamfHelper}" -windowType utility -title "Self Service Upgrade" -heading "Upgrade complete." -description "Self Service has been successfully upgraded. You may now re-open Self Service to access software installations and maintenance utilities. Please contact ITS if you need additional assistance." -button1 "Ok" -icon /Applications/Self\ Service.app/Contents/Resources/Self\ Service.icns
flog "Alerted user migration finished"

# self destruct
flog "💣 Self destruct! 💣"
rm "$0"
