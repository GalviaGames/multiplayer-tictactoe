FROM openjdk:11-jdk-bullseye

# copy shortcut scripts
COPY ./scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*

# download bob.jar and dmengine_headless
RUN "download.sh"

# update file permissions
RUN chown root:root /usr/local/bin/*

ENTRYPOINT [ "bob" ]
