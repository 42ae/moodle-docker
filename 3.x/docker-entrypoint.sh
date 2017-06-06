#!/bin/bash
set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

if [[ "$1" == apache2* ]]; then
  if ! [ -e "index.php" -a -e "version.php" ]; then
    echo >&2 "Moodle not found in $PWD - copying now..."
    if [ "$(ls -A)" ]; then
      echo >&2 "WARNING: $PWD is not empty - press Ctrl+C now if this is an error!"
      ( set -x; ls -A; sleep 10 )
    fi
    tar cf - --one-file-system -C /usr/src/moodle . | tar xf -
    echo >&2 "Complete! Moodle has been successfully copied to $PWD"
  fi

  envs=(
    MOODLE_DB_TYPE
    MOODLE_DB_HOST
    MOODLE_DB_PORT
    MOODLE_DB_NAME
    MOODLE_DB_USER
    MOODLE_DB_PASSWORD
    MOODLE_DB_PREFIX
    MOODLE_WWW_ROOT
    MOODLE_DATA_ROOT
  )
  haveConfig=
  for e in "${envs[@]}"; do
    file_env "$e"
    if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
      haveConfig=1
    fi
  done

  # linking backwards-compatibility
  if [ -n "${!MYSQL_ENV_MYSQL_*}" ]; then
    haveConfig=1
    # host defaults to "mysql" below if unspecified
    : "${MOODLE_DB_USER:=${MYSQL_ENV_MYSQL_USER:-root}}"
    if [ "$MOODLE_DB_USER" = 'root' ]; then
      : "${MOODLE_DB_PASSWORD:=${MYSQL_ENV_MYSQL_ROOT_PASSWORD:-}}"
    else
      : "${MOODLE_DB_PASSWORD:=${MYSQL_ENV_MYSQL_PASSWORD:-}}"
    fi
    : "${MOODLE_DB_NAME:=${MYSQL_ENV_MYSQL_DATABASE:-}}"
  fi

  # only touch "config-dist.php" if we have environment-supplied configuration values
  if [ "$haveConfig" ]; then
    : "${MOODLE_DB_TYPE:=mysqli}"
    : "${MOODLE_DB_HOST:=database}"
    : "${MOODLE_DB_PORT:=3306}"
    : "${MOODLE_DB_NAME:=moodle}"
    : "${MOODLE_DB_USER:=root}"
    : "${MOODLE_DB_PASSWORD:=}"
    : "${MOODLE_DB_PREFIX:=mdl_}"
    : "${MOODLE_WWW_ROOT:=}"
    : "${MOODLE_DATA_ROOT:=/var/www/moodledata}"


    if [ ! -e "config.php" ]; then
      mv config-dist.php config.php
      chown www-data:www-data config.php
    fi

    # see http://stackoverflow.com/a/2705678/433558
    sed_escape_lhs() {
      echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
    }
    sed_escape_rhs() {
      echo "$@" | sed -e 's/[\/&]/\\&/g'
    }
    php_escape() {
      php -r 'var_export(('$2') $argv[1]);' -- "$1"
    }
    set_config() {
      key="$1"
      value="$2"
      var_type="${3:-string}"
      start="(\\\$CFG->)$(sed_escape_lhs "$key")\s*="
      end=";.*"
      # port is defined as a multidimentional array in config.php
      if [ "$key" == "dbport" ]; then
        start="(['\"])$(sed_escape_lhs "$key")\2\s*=>"
        end=",.*"
      fi
      sed -ri -e "s/($start\s*).*($end)$/\1$(sed_escape_rhs "$(php_escape "$value" "$var_type")")\3/" config.php
    }

    set_config 'dbtype'   "$MOODLE_DB_TYPE"
    set_config 'dbhost'   "$MOODLE_DB_HOST"
    set_config 'dbport'   "$MOODLE_DB_PORT"
    set_config 'dbname'   "$MOODLE_DB_NAME"
    set_config 'dbuser'   "$MOODLE_DB_USER"
    set_config 'dbpass'   "$MOODLE_DB_PASSWORD"
    set_config 'prefix'   "$MOODLE_DB_PREFIX"
    set_config 'wwwroot'  "$MOODLE_WWW_ROOT"
    set_config 'dataroot' "$MOODLE_DATA_ROOT"

    TERM=dumb php -- <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

$stderr = fopen('php://stderr', 'w');

$host = getenv('MOODLE_DB_HOST');
$port = getenv('MOODLE_DB_PORT');
$user = getenv('MOODLE_DB_USER');
$pass = getenv('MOODLE_DB_PASSWORD');
$dbName = getenv('MOODLE_DB_NAME');
$socket = null;

$maxTries = 10;
do {
  $mysql = new mysqli($host, $user, $pass, '', $port, $socket);
  if ($mysql->connect_error) {
    fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
    --$maxTries;
    if ($maxTries <= 0) {
      exit(1);
    }
    sleep(3);
  }
} while ($mysql->connect_error);

if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($dbName) . '`')) {
  fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
  $mysql->close();
  exit(1);
}

$mysql->close();
EOPHP
  fi

  # now that we're definitely done writing configuration, let's clear out the relevant envrionment variables (so that stray "phpinfo()" calls don't leak secrets from our code)
  for e in "${envs[@]}"; do
    unset "$e"
  done
fi

exec "$@"