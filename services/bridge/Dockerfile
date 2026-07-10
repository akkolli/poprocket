FROM golang:1.25.12-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/bridge ./cmd/bridge

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 poprocket \
    && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin poprocket \
    && install -d -m 0700 -o poprocket -g poprocket /home/poprocket/.ssh
COPY --from=build /out/bridge /bridge
USER poprocket:poprocket
EXPOSE 6567
ENTRYPOINT ["/bridge"]
