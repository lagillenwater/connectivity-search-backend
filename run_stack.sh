#!/usr/bin/env bash

# this script uses the docker-compose.yml file to do the following:
# - create a .env file from .env.TEMPLATE, but prepopulated with random secrets
# - download large data dependencies, e.g. the postgres database dump
# - build any required images, then run the backend, postgres, and neo4j containers

set -euo pipefail

# ================================================================
# == download data dependencies
# ================================================================

mkdir -p ./data/postgres
mkdir -p ./data/neo4j

CONNECTIVITY_SEARCH_DB_URL="https://storage.googleapis.com/connectivity-search/db/2021-01-12/connectivity-search-pg_dump.sql.gz"

# download the postgres database dump if it doesn't exist
if [ ! -f ./data/postgres/connectivity-search-pg_dump.sql.gz ]; then
    echo "Downloading postgres database dump..."
    curl -L -o ./data/postgres/connectivity-search-pg_dump.sql.gz "${CONNECTIVITY_SEARCH_DB_URL}"
    echo "Downloaded postgres database dump."
fi


# ================================================================
# == set up .env file
# ================================================================

# helper that replaces an environment variable in .env with a random secret if it is missing
# args:
#  $1: the environment variable name to check
#  $2: the length of the random secret to generate (default: 16)
replace_env_var_with_secret() {
    local field="$1"
    local length="${2:-16}"
    if grep -q -e "^${field}=$" .env; then
        echo "Filling in missing ${field} value in .env"
        sed -i '' -E "s|^(${field}=)(.*)|\1$(openssl rand -hex ${length})|g" .env
    fi
}

# if .env doesn't exist, copy it from .env.TEMPLATE
if [ ! -f .env ]; then
    cp .env.TEMPLATE .env
    echo "Created .env file from .env.TEMPLATE"
fi

# replace any missing secret environment variables with random secrets
replace_env_var_with_secret POSTGRES_PASSWORD
replace_env_var_with_secret DJANGO_SECRET_KEY 32

# ================================================================
# == defintitions: preload postgres, neo4j databases
# ================================================================

# this section defines functions to preload the postgres and neo4j databases.
# preloading only occurs if the user hasn't specified any arguments to the script,
# otherwise those args are passed directly to docker compose.

# helper func to monitor one or more services until they are healthy.
# (note that they're checked in order, so a slow service earlier in the list
# will block a faster one. the command guarantees that it won't exit until
# all services are healthy, though.)
wait_for_healthy() {
  for svc in "$@"; do
    container_id=$( docker compose ps -q "${svc}" )
    echo "Waiting for ${svc} (${container_id}) to become healthy..."

    # Start tailing logs in the background
    docker compose logs -f "${svc}" &
    log_pid=$!

    # Wait for the service to become healthy
    until [ "$(docker inspect --format='{{.State.Health.Status}}' ${container_id})" = "healthy" ]; do
      sleep 2
    done

    # Stop the background log tail when healthy
    echo "Done! killing logs"
    kill "$log_pid"
    # wait "$log_pid" 2>/dev/null

    # once healthy, print a message and the service status
    echo "${svc} is healthy"
    docker compose ps ${svc}
    echo ""
  done
}

# this function attempts to "warm up" the databases by running the db and neo4j services
# and waiting for them to become healthy. this is useful for preloading the databases
# before running the stack, so that the first request to the backend doesn't take a long time
# to load the databases.
# NOTE: at the moment it's disabled, but we might re-enable it if there's interest
preload_dbs() {
  echo "* Preloading databases..."
  echo "NOTE: this can take a while the first time"
  echo " - the postgres database takes ~30 minutes to load"
  echo " - the neo4j database takes ~10 minutes to load"

  # if the services are already up and healthy, don't preload again
  if docker compose ps -q db neo4j | xargs docker inspect --format '{{.State.Health.Status}}' | grep -q 'healthy'; then
    echo "  ...Databases already preloaded, skipping."
    return 0
  fi

  # run the db and neo4j services to preload the databases
  # note that, while this will occur each time the stack starts,
  # this should be quick once the databases have loaded
  # we use the docker-compose.loading.yml file to make their healthchecks very liberal
  docker compose \
    -f docker-compose.yml -f docker-compose.loading.yml \
    up --build -d db neo4j && \
  wait_for_healthy neo4j db

  echo "  ...Databases preloaded."
}

# ================================================================
# == launch the stack
# ================================================================

if [ "$#" -gt 0 ]; then
    # if any args are supplied, run docker compose with them
    docker compose $@
else
    # # otherwise, build the stack, run it, and tail the logs
    # docker compose up --build -d && \
    # docker compose logs -f

    # # first, ensure the databases are preloaded
    # [[ "${SKIP_PRELOAD:-0}" = "1" ]] \
    #   && echo "* Skipping preloading, since SKIP_PRELOAD=1" \
    #   || preload_dbs

    # build and attach, so we don't have to wait until everything is healthy
    docker compose up --build
fi
