FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends tinyproxy-bin \
  && rm -rf /var/lib/apt/lists/*

COPY tinyproxy.conf allowlist /etc/tinyproxy/

USER nobody
ENTRYPOINT ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
