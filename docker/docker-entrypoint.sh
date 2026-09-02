#!/usr/bin/env bash
set -Eeuo pipefail

file_env() {
    local variable="$1"
    local file_variable="${variable}_FILE"
    local default_value="${2:-}"

    if [ -n "${!variable:-}" ] && [ -n "${!file_variable:-}" ]; then
        echo >&2 "error: both ${variable} and ${file_variable} are set (but are exclusive)"
        exit 1
    fi

    local value="$default_value"
    if [ -n "${!variable:-}" ]; then
        value="${!variable}"
    elif [ -n "${!file_variable:-}" ]; then
        value="$(< "${!file_variable}")"
    fi

    export "${variable}=${value}"
    unset "$file_variable"
}

moodle_environment=(
    MOODLE_DB_TYPE
    MOODLE_DB_HOST
    MOODLE_DB_PORT
    MOODLE_DB_NAME
    MOODLE_DB_USER
    MOODLE_DB_PASSWORD
    MOODLE_DB_PREFIX
    MOODLE_WWW_ROOT
    MOODLE_DATA_ROOT
    MOODLE_REVERSE_PROXY
    MOODLE_SSL_PROXY
)

have_config=''
for variable in "${moodle_environment[@]}"; do
    file_env "$variable"
    if [ -n "${!variable}" ]; then
        have_config=1
    fi
done

: "${MOODLE_DB_TYPE:=mysqli}"
: "${MOODLE_DB_HOST:=database}"
: "${MOODLE_DB_PORT:=3306}"
: "${MOODLE_DB_NAME:=moodle}"
: "${MOODLE_DB_USER:=root}"
: "${MOODLE_DB_PASSWORD:=}"
: "${MOODLE_DB_PREFIX:=mdl_}"
: "${MOODLE_WWW_ROOT:=http://localhost}"
: "${MOODLE_DATA_ROOT:=/var/www/moodledata}"
: "${MOODLE_REVERSE_PROXY:=false}"
: "${MOODLE_SSL_PROXY:=false}"

if [ "$(id -u)" = '0' ]; then
    mkdir -p "$MOODLE_DATA_ROOT"
    chown www-data:www-data "$MOODLE_DATA_ROOT"
    chmod 0750 "$MOODLE_DATA_ROOT"
fi

if [ -n "$have_config" ] && [ ! -e /var/www/html/config.php ]; then
    php /usr/local/bin/docker-moodle-config /var/www/html/config.php
    if [ "$(id -u)" = '0' ]; then
        chown www-data:www-data /var/www/html/config.php
    fi
fi

for variable in "${moodle_environment[@]}"; do
    unset "$variable"
done

if [ "${1:-}" = 'moodle-cron' ]; then
    interval="${MOODLE_CRON_INTERVAL:-60}"
    case "$interval" in
        ''|*[!0-9]*)
            echo >&2 'error: MOODLE_CRON_INTERVAL must be a positive integer'
            exit 1
            ;;
    esac
    if [ "$interval" -lt 1 ]; then
        echo >&2 'error: MOODLE_CRON_INTERVAL must be a positive integer'
        exit 1
    fi
    if [ ! -e /var/www/html/config.php ]; then
        echo >&2 'error: Moodle cron requires a configured Moodle installation'
        exit 1
    fi

    cron_options=()
    if grep -q -- '--keep-alive' /var/www/html/admin/cli/cron.php; then
        cron_options+=(--keep-alive=0)
    fi

    trap 'exit 0' INT TERM
    while true; do
        if [ "$(id -u)" = '0' ]; then
            su -s /bin/sh www-data -c "php /var/www/html/admin/cli/cron.php ${cron_options[*]}"
        else
            php /var/www/html/admin/cli/cron.php "${cron_options[@]}"
        fi
        sleep "$interval" &
        wait $!
    done
fi

exec "$@"
