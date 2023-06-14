# PostgreSQL backup

## Description

The provided code is a shell script that defines and executes a function called chkParameters(). This function is responsible for checking various parameters and configurations before initiating a backup process for a PostgreSQL database.

1. The function starts by setting the _chk_RC variable to 0, which will be used to track the status of the parameter checks.
3. Checks if the pg_basebackup command exists.
4. Checks if the backup's home directory (PGBCK_BACKUP_HOME) is specified. If it is, it iterates through a list of discarded path criteria (PGBCK_DISCARDED_PATH) and checks if the backup home matches any of the criteria.
5. If no match is found in the discarded path criteria, the code checks if the backup home matches any of the allowed path criteria (PGBCK_ALLOWED_PATH).
6. Checks if the backup home directory is a mount point or has a mount point parent.
7. Checks if the PGBCK_KEEP_BACKUP_DEST variable is set to "true" or "false".
8. Checks the database connection variables (PGBCK_DBHOST_SOURCE, PGBCK_DBPORT_SOURCE, PGBCK_DBUSER_SOURCE, PGBCK_DBPWD_SOURCE). If PGBCK_DBHOST_SOURCE is specified, checks if PGBCK_DBPORT_SOURCE is specified. If both variables are specified, it attempts to establish a TCP connection to the source database server. Similar checks are performed for the other database connection variables (PGBCK_DBUSER_SOURCE, PGBCK_DBPWD_SOURCE).
9. Dynamically creates the backup command (PGBCK_CMD) based on the database connection variables. It also checks if a pgpass file or the PGPASSFILE environment variable is present and uses it to skip the password prompt if the file is found. Finally, checks if PGBCK_DBPWD_SOURCE is specified and sets the PGPASSWORD environment variable if it is.
10. Checks the retention settings (PGBCK_RETENTION_TYPE, PGBCK_RETENTION_LIMIT) and sets the PGBCK_RETENTION_TYPE to a default value if necessary.
11. Prints the status of the parameter checks (warnings, errors) and returns the _chk_RC value.

## Parameters

|Parameter|Type|Default value|Description|
|--|--|--|--|
|PGBCK_DBHOST_SOURCE|string|"dblab01"|Hostname of the secondary node for the database connection|
|PGBCK_DBPORT_SOURCE|integer|5432|Port number for the database connection|
|PGBCK_DBUSER_SOURCE|string|"postgres"|Username for the database connection|
|PGBCK_DBPWD_SOURCE|string|"postgres"|Password for the database connection. If a pgpass file or the PGPASSFILE environment variable is declared, this variable will be ignored|
|PGBCK_BACKUP_HOME|string|"/opt/backup/PostgreSQL"|Root path of the backup(s) and log(s)|
|PGBCK_KEEP_BACKUP_DEST|boolean|"false"|If true, the script checks if the PGBCK_BACKUP_DEST exists. If it exists, the current backup (and log) will be renamed, and a new backup will be created. If false, the script will overwrite the backup destination and log, deleting them before|
|PGBCK_RETENTION_TYPE|integer|0|Selects the retention type. 0: disabled, 1: redundancy, 2: time-window|
|PGBCK_RETENTION_LIMIT|integer|2|Indicates the number of backups to retain for redundancy or the time window for retaining backups|
|PGBCK_RETENTION_MAX_LIMIT|integer|7|Maximum limit for redundancy, indicating the number of backups to retain|
|PGBCK_RETENTION_MIN_LIMIT|integer|1|Minimum limit for redundancy, indicating the number of backups to retain|
|PGBCK_RETENTION_TYPE_LIST|string|("disabled", "redundancy", "time-window")|Array listing the methods used for the retention check: disabled|

## Command line syntax

```text
    This script allows to execute the pg_basebackup with retention management."
    Usage: pg_backup.sh <option>"
    where option should be:
    --help | -? : this help
    --test | -t : used to test the parameter assigned (dry-run)
```

## Examples
