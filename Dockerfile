FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -o /trmnl-dsn .

FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /trmnl-dsn /trmnl-dsn
COPY public/images /public/images
EXPOSE 3000
ENTRYPOINT ["/trmnl-dsn"]
