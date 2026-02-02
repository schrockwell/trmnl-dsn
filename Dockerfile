# Stage 1: Build
FROM ruby:3.4.2-slim AS build

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test' && \
    bundle install

COPY . .

# Stage 2: Runtime
FROM ruby:3.4.2-slim

WORKDIR /app

COPY --from=build /app /app
COPY --from=build /usr/local/bundle /usr/local/bundle

EXPOSE 3000

ENV RACK_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

CMD ["./bin/server"]
