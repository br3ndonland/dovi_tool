# syntax=docker/dockerfile:1
FROM alpine:edge
ARG DOVI_TOOL_VERSION=2.3.0 HDR10PLUS_TOOL_VERSION=1.7.1 TARGETARCH

LABEL org.opencontainers.image.description="Container image that can be used to run dovi_tool"
LABEL org.opencontainers.image.licenses="CC0-1.0"
LABEL org.opencontainers.image.source="https://github.com/br3ndonland/dovi_tool"
LABEL org.opencontainers.image.title="dovi_tool"
LABEL org.opencontainers.image.url="https://github.com/br3ndonland/dovi_tool/pkgs/container/dovi_tool"

RUN apk add --no-cache --upgrade jq mediainfo mkvtoolnix
RUN <<HEREDOC
set -e -o pipefail
case $TARGETARCH in
amd64) TOOL_ARCH="x86_64-unknown-linux-musl" ;;
arm64) TOOL_ARCH="aarch64-unknown-linux-musl" ;;
*) printf "[ERROR] Unsupported \$TARGETARCH %s" "$TARGETARCH" && exit 1 ;;
esac
DOVI_TOOL_ARCHIVE="dovi_tool-${DOVI_TOOL_VERSION}-${TOOL_ARCH}.tar.gz"
HDR10PLUS_TOOL_ARCHIVE="hdr10plus_tool-${HDR10PLUS_TOOL_VERSION}-${TOOL_ARCH}.tar.gz"
wget -P /tmp https://github.com/quietvoid/dovi_tool/releases/download/${DOVI_TOOL_VERSION}/${DOVI_TOOL_ARCHIVE}
wget -P /tmp https://github.com/quietvoid/hdr10plus_tool/releases/download/${HDR10PLUS_TOOL_VERSION}/${HDR10PLUS_TOOL_ARCHIVE}
tar -xvf /tmp/${DOVI_TOOL_ARCHIVE} -C /usr/local/bin
tar -xvf /tmp/${HDR10PLUS_TOOL_ARCHIVE} -C /usr/local/bin
rm -rf /tmp/*
HEREDOC

COPY --link ./dovi_tool_editor_config.json ./dovi_tool_generator_config.json /config/
COPY --link --chmod=755 ./entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /opt/media

ENTRYPOINT ["entrypoint.sh"]
