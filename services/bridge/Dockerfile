FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/bridge ./cmd/bridge

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/bridge /bridge
USER nonroot:nonroot
EXPOSE 6567
ENTRYPOINT ["/bridge"]
