#!/bin/bash

# create secrets.yml from env vars via envsubst
envsubst \
    < /app/dj_hetmech/secrets.yml.template \
    > /app/dj_hetmech/secrets.yml

gunicorn dj_hetmech.wsgi:application --bind 0.0.0.0:8001 \
    --access-logfile - \
    --workers=${WEB_WORKERS:-3}
