FROM debian:bookworm-slim

# One image per agent: each proxy instance gets its own allowlist and
# accepts only its own agent's subnet.
# The subnet is per compose project (compose.yaml, drive.sh); the args come
# after the install so a new subnet rebuilds only the last layers.
RUN apt-get update \
  && apt-get install -y --no-install-recommends tinyproxy-bin \
  && rm -rf /var/lib/apt/lists/*

ARG ALLOWLIST=allowlist
ARG BOX_SUBNET=10.77.0.0/24

COPY tinyproxy.conf /etc/tinyproxy/
COPY ${ALLOWLIST} /etc/tinyproxy/allowlist
RUN test -n "${BOX_SUBNET}" \
  && sed -i "s|^Allow .*|Allow ${BOX_SUBNET}|" /etc/tinyproxy/tinyproxy.conf \
  && grep -qx "Allow ${BOX_SUBNET}" /etc/tinyproxy/tinyproxy.conf

USER nobody
ENTRYPOINT ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
