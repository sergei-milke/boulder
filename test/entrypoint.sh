#!/usr/bin/env bash

set -e -u

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configure database URL symlinks
# This is required for `docker compose up` to work after commit 2197eeac7
# which reorganized database URL files into subdirectories.
# Without this, services fail with "no such file or directory" errors.
# NOTE: Added for Plesk deployment compatibility where test.sh is not used.
configure_database_endpoints() {
  local dburl_target_dir="proxysql"

  # Check if Vitess should be used instead of ProxySQL + MariaDB
  if [[ "${USE_VITESS:-false}" == "true" ]]; then
    dburl_target_dir="vitess"
    echo "Using Vitess + MySQL 8.4"
  else
    echo "Using ProxySQL + MariaDB"
  fi

  # List of database URL files that need symlinks
  local db_url_files=(
    badkeyrevoker_dburl
    cert_checker_dburl
    incidents_dburl
    revoker_dburl
    sa_dburl
    sa_ro_dburl
  )

  echo "Configuring database URL symlinks from dburls/${dburl_target_dir}/ ..."

  # Remove any existing symlinks to avoid conflicts
  rm -f "${DIR}/../test/secrets/"*_dburl 2>/dev/null || true

  # Create symlinks from the appropriate subdirectory
  for file in "${db_url_files[@]}"; do
    ln -sf "dburls/${dburl_target_dir}/${file}" "${DIR}/../test/secrets/${file}"
  done

  echo "Database URL symlinks configured successfully"
}

# Execute database endpoint configuration
configure_database_endpoints

# Start rsyslog. Note: Sometimes for unknown reasons /var/run/rsyslogd.pid is
# already present, which prevents the whole container from starting. We remove
# it just in case it's there.
rm -f /var/run/rsyslogd.pid
rsyslogd

DB_URL_FILES=(
  badkeyrevoker_dburl
  cert_checker_dburl
  incidents_dburl
  incidents_admin_dburl
  revoker_dburl
  sa_dburl
  sa_ro_dburl
)

configure_database_endpoints() {
  DB_STYLE="proxysql"
  export DB_ADDR="boulder-proxysql:6033"

  if [[ "${USE_VITESS}" == "true" ]]
  then
    DB_STYLE="vitess"
    export DB_ADDR="boulder-vitess:33577"
  fi

  SECRETS_DIR="${BOULDER_CONFIG_DIR}/${DB_STYLE}"

  # Configure DBURL symlinks
  rm -f test/secrets/*_dburl || true
  for file in ${DB_URL_FILES:+${DB_URL_FILES[@]+"${DB_URL_FILES[@]}"}}
  do
    ln -sf "../../${SECRETS_DIR}/${file}" "test/secrets/${file}"
  done
}

# Defaults to MariaDB/ProxySQL unless USE_VITESS is true.
configure_database_endpoints

# make sure we can reach mariadb and proxysql
./test/wait-for-it.sh boulder-mariadb 3306
./test/wait-for-it.sh boulder-proxysql 6033

# make sure pkimetal's unix socket is ready
./test/wait-for-socket.sh /var/run/pkimetal/pkimetal.sock

if [[ $# -eq 0 ]]; then
    exec python3 ./start.py
fi

exec "$@"
