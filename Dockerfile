# u5g agent: probes, watchdog and their schedule (supercronic). State, keys and logs live in the /data volume.
# Built and published by .github/workflows/agent-image.yml (linux/amd64).
FROM alpine:3.23@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63

ARG SUPERCRONIC_VERSION=v0.2.49
ARG SUPERCRONIC_SHA256=a53ae236602c7338aba3fbaff40bda6300eae3b9fedb8261eb06cfe3724430c1

RUN apk add --no-cache bash curl openssh-client iputils iproute2 gawk util-linux coreutils tzdata python3 tcpdump \
 && wget -qO /usr/local/bin/supercronic "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
 && echo "${SUPERCRONIC_SHA256}  /usr/local/bin/supercronic" | sha256sum -c - \
 && chmod 755 /usr/local/bin/supercronic

COPY agent/ /app/
RUN chmod 755 /app/*.sh

ENV TZ=Europe/Helsinki D=/data DIR=/data PROBE=/app/probe-light.sh
HEALTHCHECK --interval=60s --timeout=5s --start-period=180s \
  CMD test $(( $(date +%s) - $(stat -c %Y /data/state/light.log 2>/dev/null || echo 0) )) -lt 300
ENTRYPOINT ["/app/init.sh"]
