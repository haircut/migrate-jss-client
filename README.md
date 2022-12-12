# ARCHIVED

This technique is no longer valid, so the repository is archived.

## Migrate JSS Client(s)

A tool to move clients from one JSS to another.

## Why?

Our organization had a need to migrate clients from an old, on-premise JSS to a
cloud-hosted instance. Since this migration requires more than a simple DNS
update to reflect a new hostname, we have to actually unenroll the clients from
the on-premise JSS, then enroll them to our cloud instance. Sounds like manual
work. Icky.

To complicate matters, we rely on MDM to manage devices. While pushing a new
QuickAdd package to clients on the on-premise instance would mostly handle the
migration, this leaves computers in a non-MDM-manageable state on the new
instance. No bueno.

So we have to completely unenroll the device from `$old_JSS` and then enroll it
to `$new_JSS` as a two-step procedure.

This solution allows us to automate the process or provide it as a Self Service
item for our users. After completion, the device is enrolled in the new JSS,
correctly managed, and totally ready for some MDM love.

## How?

The tool consists of 3 items:

- An embedded **QuickAdd package** that handles enrollment to the _new_ JSS
- A **shell script** which unenrolls the device from the _old_ JSS, runs the
  QuickAdd package, then cleans up after itself
- ...and a **LaunchDaemon** to initiate the whole process

The LaunchDaemon, once loaded, executes the script to manage the migration
process. When packaged, this tool's `postinstall` script will load the
LaunchDaemon for you – installing the package effectively begins the migration.

## What does the script do?

- Alerts the user, if running in "interactive" mode.
- Closes _Self Service_ if it's open.
- Attempts to remove the MDM profile using the `jamf` binary. If this fails,
  attempts to remove the MDM profile using the `profiles` binary. If this too
  fails, forcibly deletes the MDM profile from `/var/db/ConfigurationProfiles`.
- Removes the management framework, effectively unenrolling the device.
- Installs the QuickAdd package to enroll the device to the _new JSS_.
- Deletes the QuickAdd package
- Checks the connection to the _new JSS_.
- Enforces the new management framework and enables MDM.
- Unloads and deletes the LaunchDaemon.
- Alerts the user the process is complete, if running in "interactive" mode.
- Self-destructs to leave no trace.
- Pours you a refreshing beverage of your choice 🍻

...oh. And it also records all this to a log. More on that later.

## Requirements

- Ability to create upload packages and create policies on your _old JSS_
- JAMF Recon app
- [munkipkg](https://github.com/munki/munki-pkg) to package it all up

## Setting up the tool

1. Clone the repo
2. Use JAMF **Recon** to create a multi-use QuickAdd package. ([instructions](http://docs.jamf.com/9.9/casper-suite/administrator-guide/QuickAdd_Packages_Created_Using_Recon.html)).
3. Save the QuickAdd package to `payload/tmp/QuickAdd.pkg`.
4. Customize `payload/tmp/migrate-jss-client.sh` if required. By default, the
   migration runs in "silent" mode.
5. Run munkipkg (`munkipkg migrate-jss-client`) to package it all up.
6. Upload the resultant migrate-jss-client-{version}.pkg to your _old JSS_.
7. Create a policy on your _old JSS_ to install the package.

## Setting up an automated migration policy

By default this tool runs in automated or "silent" mode. This is intended for
performing migrations in the background with no user interaction or alerts.

1. Create a new policy and give it a fun name, like "Migrate Client to New JSS."
   Set a "Site" and "Category" if applicable.
2. Set a "Trigger" – _Login_ or _Recurring Check-in_ are most appropriate.
3. Set the "Execution Frequency" as "Once per computer."
4. In the "Packages" section, add your `migrate-jss-client-{version}.pkg` set
   with the option to "Install" the package.
5. Leave the other payloads blank; we don't need to reboot or update inventory,
   etc.
6. Set an appropriate **Scope**. You may need to set up Smart Groups or Static
   Groups if you don't want to target "All computers." See "Recommendations" for
   more detail on scoping an automated deployment.
7. Save the policy.

Your scoped clients should begin automatically migrating when they next hit the
configured trigger.

## Setting up a Self Service, user-initiated policy

TODO

## Configuration

### `migrate-jss-client.sh`

Take a look at `payload/tmp/migrate-jss-client.sh`; you may want to change some
of the defaults. While most of the options are documented within the script,
some require detailed explanation.

###### `old_jss_url`
The URL of your **OLD** JSS. This is your current JSS to which the clients you
are moving are currently enrolled.

###### `new_jss_url`
The URL of your **NEW** JSS. This is your "destination" JSS to which the
clients will be enrolled at the completion of the migration.

###### `runmode`
"`silent`" or "`interactive`"

By default, `migrate-jss-client` runs in "`silent`" mode which is designed to
execute the migration in the background with no user interaction or alerts.

Since the script closes Self Service – or for other reasons your determine –
you may wish to instead alert the user via `jamfHelper` GUI windows at the
beginning and end of the process. See "Recommendations" for a specific use
case.

###### `mdm_uid`
The UID of the MDM profile configured on the clients. This is used as a backup
if the `jamf` binary is unable to remove the MDM profile. The default here is
the UID common to most management systems; you shouldn't need to change it
unless you have a customized MDM scenario.

###### `mdm_filename`
The filename of the MDM profile as it appears in
`/var/db/ConfigurationProfiles` on a managed device. Used as a backup to the
above backup should both the `jamf` and `profiles` binary fail to remove the
profile. Like `mdm_uid`, the provided default is the filename common to most
management systems and should not need to be changed.

###### `launchdaemon_name`
The name of the LaunchDaemon that kicks of the migration script. If you change
this, you will also need to change the LaunchDaemon's filename, it's internal
label, and edit the `scripts/postinstall` script to reflect the new name.
There's little reason to change it since all files related to this tool are
deleted once the process is complete, so only change this if you have an
overriding need.

###### `quickadd_path`
The path to the QuickAdd package. Once you package this tool, your embedded
QuickAdd will be installed on the client system in `/tmp`. If you decided to
save your QuickAdd package with a more descriptive name, i.e.
`QuickAdd-my-new-jss.pkg`, to better organize your files, you will need to
reflect that filename here.

###### `log_file_path`
The path to the log file which contains a record of the client's migration.
See "Monitoring Logs" for tips on pulling the log into your _new JSS_ for
review.

###### UI Options

I feel each is adequately documented and explained within the script; no use
rehashing them here.

## Recommendations

TODO
