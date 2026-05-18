FROM ruby:4.0.3-slim

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential libpq-dev imagemagick pkg-config \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock* ./
RUN bundle install

COPY . .

ENV APP_ENV=production RACK_ENV=production
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
