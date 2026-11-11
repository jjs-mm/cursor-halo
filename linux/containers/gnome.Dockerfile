# BASE_IMAGE is resolved to a pinned multi-architecture manifest by the test script.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ENV DEBIAN_FRONTEND=noninteractive
COPY install-ci-dependencies.sh /usr/local/bin/install-ci-dependencies
RUN bash /usr/local/bin/install-ci-dependencies \
       bash python3 nodejs dbus dbus-x11 gjs gnome-shell gnome-shell-extension-prefs \
       xwayland gsettings-desktop-schemas libgl1-mesa-dri mesa-utils librsvg2-common fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
COPY gnome-entrypoint.sh /usr/local/bin/cursor-halo-gnome-test
RUN chmod 755 /usr/local/bin/cursor-halo-gnome-test
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/cursor-halo-gnome-test"]
