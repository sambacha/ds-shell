#!/usr/bin/env sh
export opt_event='-'
# Linux lacks SMF and the notion of an FMRI event, but always set this property
# because the SUNW program does. The dash character is the default.
SNAPPROP="-o com.sun:auto-snapshot-desc='$opt_event'"

# ISO style date; fifteen characters: YYYY-MM-DD-HHMM
# On Solaris %H%M expands to 12h34.
# If the --local-tz flag is set use the system's timezone.
# Otherwise, the default is to use UTC.
if [ -n "$opt_local_tz" ]
then
	DATE=$(date +%F-%H%M)
else
	DATE=$(date --utc +%F-%H%M)
fi
