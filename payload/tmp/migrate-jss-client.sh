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

# MDM profile filename
# Used only in last-ditch scenarios if the profile is being stubborn, or the
# Mac is in an incorrectly managed state wherein an MDM profile marked
# unremovable is present, but the jamf binary and profiles binary can't remove
# it. The default provided is the default name installed by the JSS.
mdm_filename="MDM_ComputerPrefs.plist"

# LaunchDaemon name
# The default value is usually best – it will be deleted anyway – but if your
# environment calls for it, edit away. Be sure to change the value in the
# /scripts/postinstall script as well.
# NOTE: do NOT include the .plist extension!
launchdaemon_name="com.github.haircut.migrate-jss-client"

# QuickAdd path
# Full path to the QuickAdd package. If you followed the instructions in the
# README, the default is fine.
quickadd_path="/tmp/QuickAdd.pkg"

# Log file path
log_file_path="/var/log/jss-client-migration.log"

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
write_log(){
    echo "${1}"
    echo "$(date "+%Y-%m-%d %H:%M:%S") ${1}" | tee -a "${log_file_path}"
}

###############################################################################
# main program                                                                #
###############################################################################

write_log "🎉 Beginning JSS migration 🎉"

# Make sure we're actually connected to the old JSS
if echo "$(${jamf} checkJSSConnection)" | grep -q "${old_jss_url}"; then
    write_log "...still connected to the old JSS ${old_jss_url}"
fi

if [[ "${runmode}" == "interactive" ]]; then
    "${jamfHelper}" -windowType utility -title "${window_title}" -heading "${heading_pre}" -description "${body_pre}" -button1 "Ok" -icon "${icon}"
    write_log "...alerted user"
fi
# wait 5 seconds for  good measure
sleep 5

# close self service if running
ss_pid=$(pgrep "Self Service")
if [[ $ss_pid ]]; then
    write_log "Self Service is running"
    osascript -e "tell application \"Self Service\" to quit"
    write_log "...Closed Self Service"
fi

# remove the mdm profile
write_log "Attempting to remove MDM profile"
"${jamf}" removeMdmProfile
if [[ $? -gt 0 ]]; then
    write_log "...unable to remove MDM profile via jamf binary"
    write_log "...attempting to remove MDM profile by force"
    profiles -R -p "${mdm_uid}"
    if [[ $? -gt 0 ]]; then
        write_log "...unable to remove MDM profile by force"
        write_log "...attempting last-ditch effort to delete the plist"
        rm -f "/var/db/${mdm_filename}"
        if [[ $? -gt 0 ]]; then
            write_log "...completely unable to remove the MDM profile"
        fi
        write_log "☠️☠️☠️ this device may not be properly managed on the new JSS ☠️☠️☠️"
    else
        write_log "...successfully removed the MDM profile by force"
    fi
else
    write_log "...successfully removed the MDM profile"
fi

# remove the current jamf framework
write_log "Removing JAMF framework"
"${jamf}" removeFramework
if [[ ! $(which jamf) ]]; then
    write_log "...successfully removed the JAMF framework"
else
    write_log "...it doesn't appear the framework was removed; check the device to confirm proper enrollment to the new JSS"
fi

# run the new quickadd
write_log "Installing new quickadd"
write_log "============================"
/usr/sbin/installer -pkg "${quickadd_path}" -target "/" | tee -a "${log_file_path}"
write_log "============================"
write_log "Finished installing new quickadd"

# delete the quickadd
rm "${quickadd_path}"
write_log "Removed QuickAdd package"

# sleep again
sleep 10

# TODO: check that we are connected to the new JSS

# manage and enable mdm
write_log "Managing machine"
"${jamf}" manage
write_log "Enabling MDM"
"${jamf}" mdm

# stop, unload, remove launchdaemon
write_log "Removing launchd job"
launchctl stop "${launchdaemon_name}"
launchctl unload "/Library/LaunchDaemons/${launchdaemon_name}.plist"
rm "/Library/LaunchDaemons/${launchdaemon_name}.plist"
write_log "Removed launchd job"

write_log "Managing machine again"
"${jamf}" manage

sleep 20

write_log "Re-opening Self Service"
"${jamfHelper}" -windowType utility -title "${window_title}" -heading "${heading_post}" -description "${body_post}" -button1 "Ok" -icon "${icon}"
write_log "Alerted user migration finished"

# self destruct
write_log "💣 Self destruct! 💣"
rm "$0"
