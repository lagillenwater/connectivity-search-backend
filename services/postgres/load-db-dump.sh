#!/bin/bash

# the /var/lib/postgresql/data/db_dump_loaded is a sentinel file that indicates that the dump is finished loading;
# this is part of the healthcheck for the db to ensure it's actually loaded with data
rm /var/lib/postgresql/data/db_dump_loaded 2>/dev/null || true

# Adjust persistent settings before loading
echo "* Enabling persistent settings for loading the database dump..."
psql --user=${POSTGRES_USER} --dbname=${POSTGRES_DB} <<EOF
ALTER SYSTEM SET max_wal_size = '8GB';
ALTER SYSTEM SET wal_level = minimal;  -- Only safe if this is a new/fresh DB
SELECT pg_reload_conf();
EOF

# if the dump ends in .dump, use pg_restore; otherwise, use psql
if [[ "${POSTGRES_DUMP_LOCATION}" == *.dump ]]; then
    echo "* Loading database dump from ${POSTGRES_DUMP_LOCATION} using pg_restore..."
    time pg_restore --user=${POSTGRES_USER} --dbname=${POSTGRES_DB} \
        --no-owner --no-privileges \
        --jobs=8 "${POSTGRES_DUMP_LOCATION}"
else
    # Load the database with per-session settings
    echo "* Loading database dump from ${POSTGRES_DUMP_LOCATION} via psql..."
    time (
        (
            echo "BEGIN;"
            echo "SET synchronous_commit TO OFF;"
            echo "SET maintenance_work_mem TO '1GB';"
            echo "SET work_mem TO '128MB';"
            zcat ${POSTGRES_DUMP_LOCATION}
            echo "COMMIT;"
        ) | psql --user=${POSTGRES_USER} --dbname=${POSTGRES_DB}
    )
fi

# Restore persistent settings to normal
echo "* Undoing database dump loading settings..."
psql --user=${POSTGRES_USER} --dbname=${POSTGRES_DB} <<EOF
ALTER SYSTEM SET max_wal_size = '1GB';
ALTER SYSTEM SET wal_level = replica;
SELECT pg_reload_conf();
VACUUM ANALYZE;
EOF

echo "Postgres database dump loaded successfully."

# touch the sentinel file to indicate that the dump has been loaded
touch /var/lib/postgresql/data/db_dump_loaded
