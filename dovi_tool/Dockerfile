FROM alpine:3.17
ARG DOVI_TOOL_VERSION=2.1.1
ARG DOVI_TOOL_ARCH=x86_64-unknown-linux-musl

LABEL org.opencontainers.image.description="Container image that can be used to run dovi_tool"
LABEL org.opencontainers.image.licenses="CC0-1.0"
LABEL org.opencontainers.image.source="https://github.com/br3ndonland/dovi_tool"
LABEL org.opencontainers.image.title="dovi_tool"
LABEL org.opencontainers.image.url="https://github.com/br3ndonland/dovi_tool/pkgs/container/dovi_tool"

RUN apk add --no-cache mediainfo jq
RUN apk add mkvtoolnix --repository http://dl-3.alpinelinux.org/alpine/edge/main
ADD https://github.com/quietvoid/dovi_tool/releases/download/${DOVI_TOOL_VERSION}/dovi_tool-${DOVI_TOOL_VERSION}-${DOVI_TOOL_ARCH}.tar.gz /tmp
RUN tar -xvf /tmp/dovi_tool-${DOVI_TOOL_VERSION}-${DOVI_TOOL_ARCH}.tar.gz -C /usr/local/bin
RUN mkdir /opt/media

COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY ./dovi_tool.config.json /config/dovi_tool.config.json

RUN rm -rf /tmp/*

WORKDIR /opt/media

ENTRYPOINT ["entrypoint.sh"]
