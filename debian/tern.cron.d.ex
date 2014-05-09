#
# Regular cron jobs for the tern package
#
0 4	* * *	root	[ -x /usr/bin/tern_maintenance ] && /usr/bin/tern_maintenance
