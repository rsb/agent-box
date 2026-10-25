FROM node:24.21.0-slim

ARG PNPM_VERSION=12.5.1
ARG CLAUDE_CODE_VERSION=2.1.296
ARG CODEX_VERSION=0.164.0
ARG SQLD_VERSION=0.24.32
ARG SQLD_SHA256=71720fc8648c19efef416efebd47145ef59b62e198770533530a858e1336879f
ARG PLAYWRIGHT_VERSION=1.63.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  ca-certificates curl git jq xz-utils ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/sqld.tar.xz \
  "https://github.com/tursodatabase/libsql/releases/download/libsql-server-v${SQLD_VERSION}/libsql-server-x86_64-unknown-linux-gnu.tar.xz" \
  && echo "${SQLD_SHA256}  /tmp/sqld.tar.xz" | sha256sum -c - \
  && tar -xJf /tmp/sqld.tar.xz -C /usr/local/bin --strip-components 1 \
  libsql-server-x86_64-unknown-linux-gnu/sqld \
  && rm /tmp/sqld.tar.xz

RUN npm install -g "pnpm@${PNPM_VERSION}" "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  "@openai/codex@${CODEX_VERSION}"

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx -y "playwright@${PLAYWRIGHT_VERSION}" install --with-deps chromium \
  && chmod -R a+rX /ms-playwright \
  && rm -rf /var/lib/apt/lists/* /root/.npm


COPY --chmod=755 entrypoint.sh /usr/local/bin/agent-entrypoint
RUN mkdir -p /workspace /home/node/.claude /home/node/.local/share/pnpm \
  && chown -R node:node /workspace /home/node

USER node
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
CMD ["claude"]
