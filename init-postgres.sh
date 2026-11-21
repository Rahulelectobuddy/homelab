#!/usr/bin/env bash
set -euo pipefail

create_db_user() {
  local user="$1"
  local pass="$2"
  local db="$3"

  echo "==> Configuring PostgreSQL user '$user' and database '$db'..."

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$user') THEN
        CREATE ROLE $user WITH LOGIN PASSWORD '$pass';
      END IF;
    END
    \$\$;
EOSQL

  if ! psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE $db OWNER $user;"
  fi

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "GRANT ALL PRIVILEGES ON DATABASE $db TO $user;"
}

create_db_user "vikunja" "${VIKUNJA_DB_PASSWORD:-vikunja_db_secret_change_me}" "vikunja"
create_db_user "paperless" "${PAPERLESS_DB_PASSWORD:-paperless_db_secret_change_me}" "paperless"
