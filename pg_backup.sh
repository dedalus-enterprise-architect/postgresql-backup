#!/bin/bash
shopt -s expand_aliases


# ----------------------------------------------------------------------------------------------------
# pg_backup_vXX.sh
# ---
# Author..............: Luca Rabezzana
# Created at..........: 2023.01.23
# Scope...............: This script allows to run a native pg_basebackup to have a backup of the
#                       whole cluster (for PostgreSQL version 10 or higher)
# ---
# Current version ....: 1.2
# ---
# Change log (the recent on top)
#
# Version      Date           Author               			Description
#
#     1.0      2023.01.23     Luca Rabezzana       	Building script.
#     1.1      2023.01.25     Luca Rabezzana       	Redundancy retention implemented.
#     1.2      2023.01.27     Luca Rabezzana       	- Time-window retention implemented.
#                                               		- Keep backup piece funtion added.
#                                               		  This function allows to keep more images
#                                               		  of backup.
#                                               		- Check TCP and PostgreSQL connection added.
# ----------------------------------------------------------------------------------------------------

# User's variables

# ---
# Database connection
# ---

# ---
# PGBCK_DBHOST_SOURCE: It's preferred to use the hostname of secondary node.
PGBCK_DBHOST_SOURCE="dblab01"
# ---
PGBCK_DBPORT_SOURCE=5432
PGBCK_DBUSER_SOURCE="postgres"
# ---
# PGBCK_DBPWD_SOURCE: If there is a pgpass file or the env variable PGPASSFILE is declared
#                     this variable will be ignored.
PGBCK_DBPWD_SOURCE="postgres"
# ---


# ---
# Destination
# ---
# PGBCK_BACKUP_HOME: It's the root path of backup(s) and log(s)
PGBCK_BACKUP_HOME="/opt/backup/PostgreSQL"
# ---
# PGBCK_KEEP_BACKUP_DEST: If true, the script checks if the PGBCK_BACKUP_DEST exists;
#                              in this case, the script will rename the current backup (and log)
#                              and later on will proceed with the new backup creation.
#                              If false, the script will overwrite the backup destination and log,
#                              deleting them before.
PGBCK_KEEP_BACKUP_DEST="false"
# ---


# ---
# Retention
# ---
# PGBCK_RETENTION_TYPE: Thanks this variable you can selects the retention type:
#                       0: disabled
#                       1: redundancy
#                       2: time-window
#
#                       You can set it by number index or description (in lower case)
PGBCK_RETENTION_TYPE=0
# ---

# ---
# PGBCK_RETENTION_LIMIT: It's possible indicate a number for redundancy or time-windows (aka more than N days).
#                        It's possible indicate a date string for the time-window, i.e. "-1 day", "-3 weeks" or "-1 month",
#                        them mean OLDER than 1 day, 3 weeks and 1 month respectively (Note the minus sign!!!).
PGBCK_RETENTION_LIMIT=2  # 0 is equal to disable the retention.
# ---





#
#
# DO NOT CHANGE THE VALUE OF THE FOLLOWING VARIABLES OR THE SCRIPT COULD BE RUN WRONG!
alias a_CURRENT_DATE='date +"%Y.%m.%d %H:%M:%S"'

PGBCK_ALLOWED_PATH=("^(\/home).+[^\/]$" "^(\/mnt).+[^\/]$" "^(\/opt).+[^\/]$" "^(\/).*[^\/.]$")
PGBCK_ALLOWED_PATH_LIST=("/" "/home" "/media" "/mnt" "/opt")
PGBCK_CMD="pg_basebackup"
# ---
# PGBCK_BACKUP_DEST: It's the path that will contains the PostgreSQL backup(s)
PGBCK_BACKUP_DEST="${PGBCK_DBHOST_SOURCE:-"_nodbhost_"}.pgbb"
# ---
PGBCK_DISCARDED_PATH=("\.+" "^(\/bin).*" "^(\/boot).*" "^(\/dev).*" "^(\/etc).*" "^(\/home)(.{0})$" "^(\/mnt)(.{0})$" "^(\/opt)(.{0})$" "^(\/proc).*" "^(\/root).*" "^(\/run).*" "^(\/sbin).*" "^(\/srv).*" "^(\/sys).*" "^(\/tmp).*" "^(\/usr).*" "^(\/var).*" "^(\/).{0}$")
PGBCK_LOG_FILE="/tmp/${PGBCK_BACKUP_DEST:-"_nodbhost_.pgbb"}.log"
PGBCK_RETENTION_MAX_LIMIT=7 # Limit of redundancy
PGBCK_RETENTION_MIN_LIMIT=1 # Limit of redundancy
# ---
# PGBCK_RETENTION_TYPE_LIST: This array lists the method used to run the retention check: disabled, redundancy or time-window.
#                            The first indicates that the retention check will be skipped.
#                            The second one means the number of backups that you desire keep up (there will be the most recent).
#                            The third means the older backups that you want delete, leaving the most recent.
PGBCK_RETENTION_TYPE_LIST=("disabled" "redundancy" "time-window") # disabled has index 0 ; redundancy has index 1 ; time-window has index 2
# ---
PGBCK_RETURN_FILE="/tmp/pgbb.rc"
PGBCK_START_DATE_BCK=`date +%Y%m%d`
PGBCK_SCRIPT_NAME="Auto PostgreSQL Backup"
PGBCK_SCRIPT_VERSION="v.1.2"
PGBCK_SCRIPT_DATE_VERSION="2023.01.27"
# ---


# Function

chkParameters() {
_chk_RC=0  # 0: all ok ; 1: warning ; 2: error
echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - I: " || echo "I: Dry-run. ")Checking parameters..." | tee -a ${PGBCK_LOG_FILE}

# ---
# Check if PostgreSQL pg_basebackup exists
# ---
    which ${PGBCK_CMD} &> /dev/null
    if [ $? -ne 0 ]; then
        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: OS: ${PGBCK_CMD} command not found. The backup will be aborted." | tee -a ${PGBCK_LOG_FILE}
        [ ${_chk_RC} -lt 2 ] && _chk_RC=2
    fi
# ---


# ---
# Check directory creation
# ---
    echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: Checking the backup's home \"${PGBCK_BACKUP_HOME}\"... \c" | tee -a ${PGBCK_LOG_FILE}
    if [ -n "${PGBCK_BACKUP_HOME}" ]; then
        for PGBCK_DIR_MATCH_CRITERIA in $(echo ${PGBCK_DISCARDED_PATH[@]});
        do
            if [[ "${PGBCK_BACKUP_HOME}" =~ ${PGBCK_DIR_MATCH_CRITERIA} ]]; then
                echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Bad value: the \"PGBCK_BACKUP_HOME\" parameter allows a path that is different by the O.S.'s. (equal to or parent by) as:" | tee -a ${PGBCK_LOG_FILE}
                echo -e "  \"., .., $(echo ${PGBCK_DISCARDED_PATH[*]} | sed -e 's/[\\.*+^{}$()0]//g' | sed -e 's/\ \/$//g' | sed -e 's/^\ //' -e 's/\ /,\ /g')\"" | tee -a ${PGBCK_LOG_FILE}
                echo -e "   except for: \"$(echo ${PGBCK_ALLOWED_PATH_LIST[@]} | sed -e 's/\ /, /g')\"." | tee -a ${PGBCK_LOG_FILE}
                [ ${_chk_RC} -lt 2 ] && _chk_RC=2
                break
            fi
        done

        if [ ${_chk_RC} -eq 0 ]; then
            _path_found="false"
            for PGBCK_DIR_MATCH_CRITERIA in $(echo ${PGBCK_ALLOWED_PATH[@]});
            do
                if [[ "${PGBCK_BACKUP_HOME}" =~ ${PGBCK_DIR_MATCH_CRITERIA} ]]; then
                    _path_found="true"
                    echo -e "OK." | tee -a ${PGBCK_LOG_FILE}

                    # Checking if the destination is a mount point or has a mount point parent.
                    _PGBCK_CHECK_BCK_HOME=${PGBCK_BACKUP_HOME}
                    while true ;
                    do
                        if [ -n "${_PGBCK_CHECK_BCK_HOME}" ]; then
                            df -h | awk '{print $6}' | grep -Fx ${_PGBCK_CHECK_BCK_HOME} >/dev/null 2>&1
                            if [ $? -eq 0 ]; then
                                break
                            else
                                _PGBCK_CHECK_BCK_HOME=$(echo ${_PGBCK_CHECK_BCK_HOME%/*})
                            fi
                        else
                            echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The path \"${PGBCK_BACKUP_HOME}\" is a regular directory. It's suggested a dedicated mount point for the \"PGBCK_BACKUP_HOME\" parameter." | tee -a ${PGBCK_LOG_FILE}
                            break
                        fi
                    done

                    echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: Keep backup destination check $([ "${PGBCK_KEEP_BACKUP_DEST:-"false"}" = "true" ] && echo "enabled" || echo "disabled")."  | tee -a ${PGBCK_LOG_FILE}
                    break
                fi
            done

            if [ "${_path_found}" = "false" ]; then
                echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Bad value: the path doesn't satisfy the match criteria \"${PGBCK_DIR_MATCH_CRITERIA}\". The \"PGBCK_BACKUP_HOME\" parameter is mandatory." | tee -a ${PGBCK_LOG_FILE}
                [ ${_chk_RC} -lt 2 ] && _chk_RC=2
            fi
        fi
    else
        echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Value not assigned: the \"PGBCK_BACKUP_HOME\" parameter is mandatory." | tee -a ${PGBCK_LOG_FILE}
        [ ${_chk_RC} -lt 2 ] && _chk_RC=2
    fi
# ---


# ---
# Check db connection variables
# ---
    _chk_connection=0
    if [ -n "${PGBCK_DBHOST_SOURCE}" ]; then
        if [ -n "${PGBCK_DBPORT_SOURCE}" ]; then
            echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: Checking the TCP connection to the source database server ${PGBCK_DBHOST_SOURCE}:${PGBCK_DBPORT_SOURCE}... \c" | tee -a ${PGBCK_LOG_FILE}
            bash -c "echo > /dev/tcp/${PGBCK_DBHOST_SOURCE}/${PGBCK_DBPORT_SOURCE}" &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "OK." | tee -a ${PGBCK_LOG_FILE}
            else
                echo -e "No connection established." | tee -a ${PGBCK_LOG_FILE}
                [ ${_chk_RC} -lt 2 ] && _chk_RC=2
                _chk_connection=1
            fi
        else
            echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Value not assigned: the \"PGBCK_DBPORT_SOURCE\" parameter is mandatory." | tee -a ${PGBCK_LOG_FILE}
            [ ${_chk_RC} -lt 2 ] && _chk_RC=2
            _chk_connection=1
        fi
    else
        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Value not assigned: the \"PGBCK_DBHOST_SOURCE\" parameter is mandatory." | tee -a ${PGBCK_LOG_FILE}
        [ ${_chk_RC} -lt 2 ] && _chk_RC=2
        _chk_connection=1
    fi


    if [ ! -n "${PGBCK_DBUSER_SOURCE}" ]; then
        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Value not assigned: the \"PGBCK_DBUSER_SOURCE\" parameter is mandatory." | tee -a ${PGBCK_LOG_FILE}
        [ ${_chk_RC} -lt 2 ] && _chk_RC=2
        _chk_connection=1
    fi


# ---


# ---
# Backup command dynamic creation & Check connection
# ---
    echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: Checking the database authentication... \c" | tee -a ${PGBCK_LOG_FILE}
    if [ ${_chk_connection} -ne 0 ]; then
        echo "skipped" | tee -a ${PGBCK_LOG_FILE}
    else
        PGBCK_CMD="${PGBCK_CMD} -h ${PGBCK_DBHOST_SOURCE} -p ${PGBCK_DBPORT_SOURCE} -U ${PGBCK_DBUSER_SOURCE} -Ft -z -Xs -R -P -v"
        _PGBCK_CHECK_DBPWD="true"

        if [ -n "${PGPASSFILE}" ] || [ -f ${HOME}/.pgpass ]; then
            psql -h ${PGBCK_DBHOST_SOURCE} -p ${PGBCK_DBPORT_SOURCE} -U ${PGBCK_DBUSER_SOURCE} -w -l &> /dev/null
            if [ $? -eq 0 ]; then
                PGBCK_CMD="${PGBCK_CMD} -w"
                _PGBCK_CHECK_DBPWD="false"
                echo -e "pgpass file found. The \"PGBCK_DBPWD_SOURCE\" parameter will be ignored." | tee -a ${PGBCK_LOG_FILE}
            fi
        fi

        if [ "${_PGBCK_CHECK_DBPWD}" = "true" ]; then
            if [ -n "${PGBCK_DBPWD_SOURCE}" ]; then
                export PGPASSWORD="${PGBCK_DBPWD_SOURCE}"
                psql -h ${PGBCK_DBHOST_SOURCE} -p ${PGBCK_DBPORT_SOURCE} -U ${PGBCK_DBUSER_SOURCE} -w -l > /dev/null
                if [ $? -eq 0 ]; then
                    PGBCK_CMD="${PGBCK_CMD} -w"
                    echo -e "OK." | tee -a ${PGBCK_LOG_FILE}
                else
                    echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: psql: an error occurred. Checks the \"PGBCK_DBUSER_SOURCE\" and/or \"PGBCK_DBPWD_SOURCE\" parameters." | tee -a ${PGBCK_LOG_FILE}
                    unset PGPASSWORD
                    [ ${_chk_RC} -lt 2 ] && _chk_RC=2
                fi
            else
                echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")E: Value not assigned: the \"PGBCK_DBPWD_SOURCE\" parameter is mandatory." | tee -a ${PGBCK_LOG_FILE}
                [ ${_chk_RC} -lt 2 ] && _chk_RC=2
            fi
        fi
    fi
# ---


# ---
# Check retention
# ---
    if [ ${PGBCK_RETENTION_TYPE} -eq 0 -o "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[0]}" ] ||
       [ ${PGBCK_RETENTION_TYPE} -eq 1 -o "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[1]}" ] ||
       [ ${PGBCK_RETENTION_TYPE} -eq 2 -o "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[2]}" ]; then
        if [[ ${PGBCK_RETENTION_TYPE} =~ ^[[:digit:]]+$ ]]; then
            PGBCK_RETENTION_TYPE=${PGBCK_RETENTION_TYPE_LIST[${PGBCK_RETENTION_TYPE}]}
        fi
        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The retention check is set to ${PGBCK_RETENTION_TYPE}. \c" | tee -a ${PGBCK_LOG_FILE}
        if [ "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[1]}" -o "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[2]}" ]; then
            if [ ! -n "${PGBCK_RETENTION_LIMIT}" ]; then
                echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")W: Value not assigned: The \"PGBCK_RETENTION_TYPE\" parameter is empty." | tee -a ${PGBCK_LOG_FILE}
                echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The retention check will be skipped." | tee -a ${PGBCK_LOG_FILE}
                PGBCK_RETENTION_TYPE="${PGBCK_RETENTION_TYPE_LIST[0]}" # Forced, so the retention will be skipped during the script running time.
                [ ${_chk_RC} -lt 1 ] && _chk_RC=1
            else
                if [ "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[1]}" ]; then # redundancy
                    if [[ ${PGBCK_RETENTION_LIMIT} =~ ^[[:digit:]]+$ ]]; then
                        if [ ${PGBCK_RETENTION_LIMIT} -gt ${PGBCK_RETENTION_MAX_LIMIT} ]; then
                            echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")W: Bad value: The max redundancy retention cannot exceed ${PGBCK_RETENTION_MAX_LIMIT} copies." | tee -a ${PGBCK_LOG_FILE}
                            echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: For safety, the new max redundancy retention will be set to ${PGBCK_RETENTION_MIN_LIMIT}." | tee -a ${PGBCK_LOG_FILE}
                            PGBCK_RETENTION_LIMIT=${PGBCK_RETENTION_MIN_LIMIT}
                            [ ${_chk_RC} -lt 1 ] && _chk_RC=1
                        fi
                        if [ ${PGBCK_RETENTION_LIMIT} -lt ${PGBCK_RETENTION_MIN_LIMIT}  ]; then
                            echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The \"PGBCK_RETENTION_LIMIT\" parameter is less than ${PGBCK_RETENTION_MIN_LIMIT} or equal to 0." | tee -a ${PGBCK_LOG_FILE}
                            echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The retention check will be skipped." | tee -a ${PGBCK_LOG_FILE}
                            PGBCK_RETENTION_TYPE="${PGBCK_RETENTION_TYPE_LIST[0]}" # Forced, so the retention will be skipped during the script running time.
                            [ ${_chk_RC} -lt 1 ] && _chk_RC=1
                        else
                            # Delete backup pieces
                            echo -e "To keep ${PGBCK_RETENTION_LIMIT} piece(s)." | tee -a ${PGBCK_LOG_FILE}
                        fi
                    else
                        echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")W: Bad value: The ${PGBCK_RETENTION_TYPE} retention allows only integer greater than 0." | tee -a ${PGBCK_LOG_FILE}
                        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The retention check will be skipped." | tee -a ${PGBCK_LOG_FILE}
                        PGBCK_RETENTION_TYPE="${PGBCK_RETENTION_TYPE_LIST[0]}" # Forced, so the retention will be skipped during the script running time.
                        [ ${_chk_RC} -lt 1 ] && _chk_RC=1
                    fi
                elif [ "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[2]}" ]; then
                    if [[ "${PGBCK_RETENTION_LIMIT}" =~ ^-{1}[[:digit:]]{1,2}[[:space:]]{0,1}(day|week|month)s?$ ]]; then
                        echo -e "To delete backup piece(s) older than ${PGBCK_RETENTION_LIMIT/-/}." | tee -a ${PGBCK_LOG_FILE}
                    else
                        echo -e "\n$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")W: Bad value: The ${PGBCK_RETENTION_TYPE} retention allows date string only (i.e. -2 days, -1 week)." | tee -a ${PGBCK_LOG_FILE}
                        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The retention check will be skipped." | tee -a ${PGBCK_LOG_FILE}
                        PGBCK_RETENTION_TYPE="${PGBCK_RETENTION_TYPE_LIST[0]}" # Forced, so the retention will be skipped during the script running time.
                        [ ${_chk_RC} -lt 1 ] && _chk_RC=1
                    fi
                fi
            fi
        fi
    else
        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")W: Bad or not assigned value: The \"PGBCK_RETENTION_TYPE\" parameter allows the following values only: ${PGBCK_RETENTION_TYPE_LIST[@]}" | tee -a ${PGBCK_LOG_FILE}
        echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: The retention check will be skipped." | tee -a ${PGBCK_LOG_FILE}
        PGBCK_RETENTION_TYPE="${PGBCK_RETENTION_TYPE_LIST[0]}" # Forced, so the retention will be skipped during the script running time.
        [ ${_chk_RC} -lt 1 ] && _chk_RC=1
    fi
# ---

    if [ "$1" = "yes" ]; then        # onlyTest = yes => dry-run of the script
        if [ "${_chk_RC}" -eq 0 ]; then
            echo -e "\nI: All is ok." | tee -a ${PGBCK_LOG_FILE}
        else
            echo -e "\nI: One or more warning(s)/error(s) found. The warning will be ignored during the execution, but checks the ${PGBCK_SCRIPT_NAME}'s settings anyway." | tee -a ${PGBCK_LOG_FILE}
        fi
        exit_rc 0
    elif [ "$1" = "no" ]; then       # onlyTest = no => complete run of the script
        if [ ${_chk_RC} -eq 0 ]; then
            echo -e "\n`a_CURRENT_DATE` - I: All is ok." | tee -a ${PGBCK_LOG_FILE}
        elif [ ${_chk_RC} -eq 1 ]; then
            echo -e "\n`a_CURRENT_DATE` - I: One or more warning(s) found, but will be ignored.\n" | tee -a ${PGBCK_LOG_FILE}
        else
            echo -e "\n`a_CURRENT_DATE` - I: One or more parameters could be wrong/unassigned or some errors occurred. Please, checks the ${PGBCK_SCRIPT_NAME}'s settings." | tee -a ${PGBCK_LOG_FILE}
            exit_rc 1
        fi


        mkdir -p ${PGBCK_BACKUP_HOME}/{log,piece} # Executed if _chk_RC is 0 or 1
        if [ $? -eq 0 ]; then
            chmod 750 ${PGBCK_BACKUP_HOME}/{log,piece} >/dev/null 2>&1
            chown -R postgres:postgres ${PGBCK_BACKUP_HOME} >/dev/null 2>&1
            PGBCK_BACKUP_DEST="${PGBCK_BACKUP_HOME}/piece/${PGBCK_BACKUP_DEST}"
            echo -e "`a_CURRENT_DATE` - I: Sub-directories created." | tee -a ${PGBCK_LOG_FILE}


            if [ "${PGBCK_KEEP_BACKUP_DEST:-"false"}" = "true" ]; then
                if [ -e ${PGBCK_BACKUP_DEST} ]; then
                    echo -e "`a_CURRENT_DATE` - I: The current \"${PGBCK_BACKUP_DEST}\" and own log will be keeped up (renamed)... \c" | tee -a ${PGBCK_LOG_FILE}
                    PGBCK_DATE=$(stat -c %y ${PGBCK_BACKUP_DEST})
                    PGBCK_DATE=${PGBCK_DATE%.*}
                    PGBCK_DATE=$(echo ${PGBCK_DATE} | sed -e 's/\-//g' | sed -e 's/\ /_T/g' | sed -e 's/\://g')

                    mv ${PGBCK_BACKUP_DEST} ${PGBCK_BACKUP_DEST}.old.${PGBCK_DATE} &> /dev/null ; [ $? -eq 0 ] && echo -e "done." | tee -a ${PGBCK_LOG_FILE}
                    mv ${PGBCK_BACKUP_HOME}/log/$(basename ${PGBCK_LOG_FILE}) ${PGBCK_BACKUP_HOME}/log/$(basename ${PGBCK_LOG_FILE}).old.${PGBCK_DATE} &> /dev/null
                else
                    echo -e "`a_CURRENT_DATE` - I: There isn't backup piece to keep." | tee -a ${PGBCK_LOG_FILE}
                fi
            else
                if [ -e ${PGBCK_BACKUP_DEST} ]; then
                    echo -e "`a_CURRENT_DATE` - I: The current \"${PGBCK_BACKUP_DEST}\" will be deleted... \c" | tee -a ${PGBCK_LOG_FILE}
                    rm -fR ${PGBCK_BACKUP_DEST} &> /dev/null ; [ $? -eq 0 ] && echo -e "done." | tee -a ${PGBCK_LOG_FILE}
                else
                    echo -e "`a_CURRENT_DATE` - I: There isn't backup piece to delete." | tee -a ${PGBCK_LOG_FILE}
                fi
            fi

            # Merge log file by initial path (/tmp) with the newer
            if [ -e ${PGBCK_LOG_FILE} ]; then
                cp -p ${PGBCK_LOG_FILE} ${PGBCK_BACKUP_HOME}/log/$(basename ${PGBCK_LOG_FILE}) &> /dev/null && \
                rm -f ${PGBCK_LOG_FILE} &> /dev/null
            fi
            [ -e ${PGBCK_RETURN_FILE} ] && rm -f ${PGBCK_RETURN_FILE} &> /dev/null

            PGBCK_LOG_FILE="${PGBCK_BACKUP_HOME}/log/$(basename ${PGBCK_LOG_FILE})"
            PGBCK_RETURN_FILE="${PGBCK_BACKUP_HOME}/log/$(basename ${PGBCK_RETURN_FILE})"
            [ -e ${PGBCK_RETURN_FILE} ] && rm -f ${PGBCK_RETURN_FILE} &> /dev/null
        else
            [ -e ${PGBCK_RETURN_FILE} ] && rm -f ${PGBCK_RETURN_FILE}
            echo -e "`a_CURRENT_DATE` - E: OS: an error occurred during the sub-directories creation." | tee -a ${PGBCK_LOG_FILE}
            echo -e "`a_CURRENT_DATE` - I: The procedure will be aborted." | tee -a ${PGBCK_LOG_FILE}
            exit_rc 1
        fi
    fi

}


exec_pg_basebackup() {
    echo -e "`a_CURRENT_DATE` - I: Calling pg_basebackup to backup to \"${PGBCK_BACKUP_DEST}\"..." | tee -a ${PGBCK_LOG_FILE}
    echo -e "`a_CURRENT_DATE` - W: The backup will include the recovery-conf/standby.signal file. If you think to restore to a master db/s, remember to delete that file before." | tee -a ${PGBCK_LOG_FILE}

    set -o pipefail
    # Update PGBCK_CMD
    PGBCK_CMD="${PGBCK_CMD} -D ${PGBCK_BACKUP_DEST}"

    (time ${PGBCK_CMD}) 2>&1 | tee -a ${PGBCK_LOG_FILE}
    RC=$?
    set +o pipefail
}


exec_retention() {
# Retention check
    if [ ${RC} -eq 0 -a "${PGBCK_RETENTION_TYPE}" != "${PGBCK_RETENTION_TYPE_LIST[0]}" ]; then # Check the right retention config
        echo -e "`a_CURRENT_DATE` - I: Looking for old backup... \c" | tee -a ${PGBCK_LOG_FILE}
        if [ "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[1]}" ];  then # redundancy
            # ---
            # Delete backup pieces
            # ---
            _backup_list=($(ls -tr ${PGBCK_BACKUP_HOME}/piece))
            _cnt_backup_list=${#_backup_list[@]}
            if [ ${_cnt_backup_list} -gt ${PGBCK_RETENTION_LIMIT} ]; then
                echo -e "$((${_cnt_backup_list}-${PGBCK_RETENTION_LIMIT})) piece(s) found." | tee -a ${PGBCK_LOG_FILE}
                _backup_list=(${_backup_list[@]:0:$((${_cnt_backup_list}-${PGBCK_RETENTION_LIMIT}))})
                echo -e "`a_CURRENT_DATE` - I: Deleting old backup(s) and log(s)..." | tee -a ${PGBCK_LOG_FILE}
                set -o pipefail
                for _file2delete in $(echo ${_backup_list[@]});
                do
                    rm -fRv ${PGBCK_BACKUP_HOME}/piece/${_file2delete} 2>&1 | tee -a ${PGBCK_LOG_FILE}
                    [ $? -ne 0 ] && echo -e "\n`a_CURRENT_DATE` - E: OS: An error occurred removing \"${_file2delete}\". " | tee -a ${PGBCK_LOG_FILE}
                    rm -fRv ${PGBCK_BACKUP_HOME}/log/${_file2delete/\.old/\.log.old} 2>&1 | tee -a ${PGBCK_LOG_FILE}
                    [ $? -ne 0 ] && echo -e "\n`a_CURRENT_DATE` - E: OS: An error occurred removing \"${_file2delete/\.old/\.log.old}\". " | tee -a ${PGBCK_LOG_FILE}
                done
                set +o pipefail
            # ---
            else
                echo -e "no piece(s) found." | tee -a ${PGBCK_LOG_FILE}
            fi
            unset _backup_list
            unset _cnt_backup_list
        elif [ "${PGBCK_RETENTION_TYPE}" = "${PGBCK_RETENTION_TYPE_LIST[2]}" ]; then  # time-window
            # ---
            # Translate to minutes
            # ---
            _date2chk=`date -d "${PGBCK_START_DATE_BCK} ${PGBCK_RETENTION_LIMIT}"` # Date explained in seconds
            _date2chk=$((`date -d "${_date2chk}" +%s` - `date -d "${PGBCK_START_DATE_BCK}" +%s`))
            _date2chk=$((${_date2chk}/60))
            # ---

            _cnt_backup_list=$(find ${PGBCK_BACKUP_HOME}/piece -daystart ! -mmin ${_date2chk} | wc -l)
            if [ ${_cnt_backup_list} -gt 0 ]; then
                echo -e "${_cnt_backup_list} piece(s) found." | tee -a ${PGBCK_LOG_FILE}
                echo -e "`a_CURRENT_DATE` - I: Deleting old backup(s) and log(s)..." | tee -a ${PGBCK_LOG_FILE}
                find ${PGBCK_BACKUP_HOME}/piece -daystart ! -mmin ${_date2chk} | xargs rm -fRv
                find ${PGBCK_BACKUP_HOME}/log -daystart ! -mmin ${_date2chk} | xargs rm -fv
            else
                echo -e "no old piece(s) found." | tee -a ${PGBCK_LOG_FILE}
            fi
            unset _cnt_backup_list
            unset _date2chk
        fi
    fi
}


help() {
    echo -e "\n****************************************************"
    echo -e "* ${PGBCK_SCRIPT_NAME} - ver. ${PGBCK_SCRIPT_VERSION} (at ${PGBCK_SCRIPT_DATE_VERSION})"
    echo -e "****************************************************"
    echo -e "\nThis script allows to execute the pg_basebackup with retention management."
    echo -e "\nUsage: $(basename $0) <option>"
    echo -e "\nwhere option should be:\n"
    echo -e "    --help | -? : this help"
    echo -e "    --test | -t : used to test the parameter assigned (dry-run).\n"
}


exit_rc() {
    RC=$1
    echo "${PGBCK_BACKUP_DEST} $([ ${RC} -eq 0 ] && echo "OK" || echo "KO")" > ${PGBCK_RETURN_FILE}
    echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: Procedure finished $([ ${RC} -eq 0 ] && echo "sucessfully." || echo "with error(s)") \n" | tee -a ${PGBCK_LOG_FILE}
    [ "${PGBCK_ONLY_TEST}" = "yes" ] && rm ${PGBCK_RETURN_FILE} ${PGBCK_LOG_FILE} &> /dev/null
    exit ${RC}
}


# Main

PGBCK_ARGS_CNT=$#           # Checks how many arguments are passed to the script.
PGBCK_ONLY_TEST="no"        # Used to identify the dry-run or complete execution of the script.

if [ ${PGBCK_ARGS_CNT} -gt 1 ]; then
    help ; exit 0
else
    while [ $# -gt 0 ]
    do
        PGBCK_ARGS_IN=$1
        PGBCK_ARGS_IN=${PGBCK_ARGS_IN:+`echo ${PGBCK_ARGS_IN,,}`}

        case ${PGBCK_ARGS_IN} in
            --test | -t)  PGBCK_ONLY_TEST="yes"
                          break
                          ;;
        --help | -? | *)  help
                          exit 0
                          ;;
        esac
        shift
    done
fi


# Check if the script is running by postgres user
[ "$(whoami)" != "postgres" ] && {
    echo "Error: The postgres user is mandatory to run the script."
    exit 1
}


echo -e "\n* ---\n* ${PGBCK_SCRIPT_NAME} ${PGBCK_SCRIPT_VERSION} (released at ${PGBCK_SCRIPT_DATE_VERSION})\n* ---\n" | tee ${PGBCK_LOG_FILE}
echo -e "$([ "${PGBCK_ONLY_TEST}" = "no" ] && echo "`a_CURRENT_DATE` - ")I: Procedure started." | tee -a ${PGBCK_LOG_FILE}


chkParameters ${PGBCK_ONLY_TEST:-"no"}
exec_pg_basebackup
exec_retention
exit_rc ${RC}
