# sql-backup-tcl
Tool for creating backups for MySQL and PostgreSQL.
The code has comments and var names in spanish, but the sample config it's translated to english. It should be enough to get an idea
on how to use it.

This script has been creating backup for my development databases and a couple ones in production. 

## Usage
Command line:

`tclsh sql-backup.tcl <config.conf>`

For automated backups create a cron job to run the script once a day providing a config file.

&copy; CopyRight Antonio Varela<br/>
Released under the MIT License
