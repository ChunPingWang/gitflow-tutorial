FROM nginx:1.27-alpine

ARG APP_VERSION=dev
ARG GIT_BRANCH=unknown
ARG GIT_SHA=unknown
ARG BUILD_ENV=local

ENV APP_VERSION=${APP_VERSION}

LABEL org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      gitflow.branch="${GIT_BRANCH}"

RUN printf '%s\n' \
  '<!doctype html>' \
  '<html lang="zh-Hant"><head><meta charset="utf-8">' \
  '<meta name="viewport" content="width=device-width,initial-scale=1">' \
  '<title>GitFlow Demo App</title>' \
  '<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:4rem auto;padding:0 1.5rem;line-height:1.7}' \
  'h1{margin-bottom:2rem}dl{display:grid;grid-template-columns:auto 1fr;gap:.5rem 1.5rem}' \
  'dt{font-weight:600;color:#555}code{background:#f4f4f5;padding:.15rem .4rem;border-radius:.25rem}</style>' \
  '</head><body><h1>GitFlow Demo App</h1><dl>' \
  "<dt>Version</dt><dd><b>${APP_VERSION}</b></dd>" \
  "<dt>Branch</dt><dd><code>${GIT_BRANCH}</code></dd>" \
  "<dt>Commit</dt><dd><code>${GIT_SHA}</code></dd>" \
  "<dt>Environment</dt><dd>${BUILD_ENV}</dd>" \
  '</dl></body></html>' \
  > /usr/share/nginx/html/index.html \
  && printf 'ok\n' > /usr/share/nginx/html/healthz

EXPOSE 80
