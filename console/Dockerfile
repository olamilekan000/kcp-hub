# syntax=docker/dockerfile:1.4

# The console image: the built UI plus a small server that serves it and
# reads the deployment's settings from CONSOLE_* environment variables.
#
#   docker build -t console console/

# The UI builds to static files that are the same on every architecture, so
# it is built once on the build platform.
FROM --platform=$BUILDPLATFORM node:24-alpine AS ui
WORKDIR /src
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build

# Pinned to the build platform so multi-arch builds cross-compile instead of
# running the toolchain under emulation.
FROM --platform=$BUILDPLATFORM golang:1.26.4 AS server
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
COPY server/ server/
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
    go build -o /out/console ./server/

FROM gcr.io/distroless/static:nonroot
COPY --from=server /out/console /console
COPY --from=ui /src/dist/ /www/
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/console"]
