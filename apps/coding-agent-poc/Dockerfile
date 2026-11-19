FROM ghcr.io/anomalyco/opencode:2.3.2@sha256:be07cc4afd6d668d91b77accf1bc4338c87b39fbacc0a61666eb003781015f5a
RUN apk add --no-cache ca-certificates curl git python3 \
    && addgroup -g 1000 poc \
    && adduser -D -H -u 1000 -G poc -h /workspace poc
USER 1000:1000
