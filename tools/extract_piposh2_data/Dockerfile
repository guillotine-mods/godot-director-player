# Runs the Piposh 2 VISE self-installer under Wine so the Director movies and
# cast libraries can be recovered without a Windows machine.
#
# piposh2.exe is "PE32 executable (GUI) Intel 80386" — 32-bit. Rather than fight
# WoW64 in a 64-bit Wine, the whole container is i386: a plain 32-bit Wine runs
# a 32-bit Windows binary, which is the configuration Wine supports best. On
# Apple Silicon this runs under the host's qemu-i386 emulation, so it is slow
# but it does not need Rosetta (which is x86-64 only and cannot help here).
#
# Pinned by digest so a rebuild years from now still gets Wine 8.0 from bookworm.
FROM --platform=linux/386 i386/debian:bookworm-slim@sha256:72b77a38b741753a64ebd7ff26c200d5eb5119f8b385409c5aaaa1aee12e9045

# xvfb/xauth: the installer is a GUI program and has no unattended switch.
# xdotool + imagemagick: drive and screenshot that GUI headlessly.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        wine \
        xvfb \
        xauth \
        xdotool \
        imagemagick \
        x11-utils \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Keep the prefix on the container's own overlay filesystem. The install writes
# ~600 MB (3141 .AIF files come along whether we want them or not); pushing that
# through a Docker Desktop bind mount under emulation is far slower, so only the
# ~147 MB of casts and movies is copied out to /out at the end.
ENV WINEPREFIX=/wine \
    WINEARCH=win32 \
    WINEDEBUG=-all \
    DISPLAY=:0

# Without this, creating the prefix pops the Mono and Gecko download dialogs,
# which in a headless run is indistinguishable from the installer hanging.
ENV WINEDLLOVERRIDES="mscoree,mshtml="

COPY extract.sh /usr/local/bin/extract.sh
RUN chmod +x /usr/local/bin/extract.sh

ENTRYPOINT ["/usr/local/bin/extract.sh"]
