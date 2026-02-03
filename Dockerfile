FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd/ cmd/
COPY internal/ internal/
RUN CGO_ENABLED=0 go build -o /trmnl-dsn ./cmd/server

FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /trmnl-dsn /trmnl-dsn
COPY public/images /public/images
EXPOSE 3000
ENTRYPOINT ["/trmnl-dsn"]
