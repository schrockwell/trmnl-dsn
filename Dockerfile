# Build stage
FROM ruby:3.4.2-alpine AS builder

WORKDIR /app

ENV BUNDLE_PATH=/app/vendor/bundle
ENV BUNDLE_WITHOUT=development:test

RUN apk add --no-cache build-base git

COPY Gemfile Gemfile.lock ./
RUN bundle install

# Runtime stage
FROM ruby:3.4.2-alpine

WORKDIR /app

ENV BUNDLE_PATH=/app/vendor/bundle
ENV RACK_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

COPY . .
COPY --from=builder /app/vendor/bundle /app/vendor/bundle

EXPOSE 3000

CMD ["bundle", "exec", "./bin/server"]
