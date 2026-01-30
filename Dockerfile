FROM ruby:3.4.2-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .

EXPOSE 3000

ENV RACK_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

CMD ["./bin/server"]
