ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}

WORKDIR /app
RUN pip install setuptools --upgrade
RUN pip install wheel uwsgi uv
COPY pyproject.toml uv.lock /app/
COPY back/pyproject.toml /app/back/pyproject.toml
COPY front/pyproject.toml /app/front/pyproject.toml
RUN uv sync --frozen --no-dev --project front
ENV PATH="/app/.venv/bin:$PATH"
# Yandex Cloud PostgreSQL CA, needed only by MODE=prod. The local dev stack
# (compose.yaml) builds with WITH_YANDEX_CA=0 so the build works offline or
# behind a proxy.
ARG WITH_YANDEX_CA=1
RUN if [ "$WITH_YANDEX_CA" = "1" ]; then \
        mkdir -p /app/.postgresql && \
        wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" -O /app/.postgresql/root.crt && \
        chmod 0600 /app/.postgresql/root.crt; \
    fi

COPY front/src /app

COPY front/run_app.sh /app/run_app.sh
RUN chmod +x /app/run_app.sh

CMD ["/app/run_app.sh"]
