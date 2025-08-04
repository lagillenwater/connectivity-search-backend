FROM python:3.8.3

# Update sources for now-archived debian repositories
RUN sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g' /etc/apt/sources.list \
 && sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list

# install a more capable envsubst drop-in replacement, i.e. that supports
# default values. in molevolvr_node and molevolvr_app, we use this to generate
# the actual slurm.conf and other config files from templates in the entrypoint
# script
RUN curl -L -o envsubst \
    "https://github.com/a8m/envsubst/releases/download/v1.4.3/envsubst-Linux-x86_64" && \
    chmod +x envsubst && \
    mv envsubst /usr/local/bin

# copy requiremnents.txt to /tmp/requirement.txt
COPY ./docker/requirements.txt /tmp/requirements.txt
# install pip dependencies with a build-time cache
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r /tmp/requirements.txt

# copy in the rest of the code
WORKDIR /app
COPY . /app

CMD ["/app/docker/launch_api.sh"]
