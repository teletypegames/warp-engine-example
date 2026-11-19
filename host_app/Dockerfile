FROM ruby:3.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  default-libmysqlclient-dev \
  git \
  tzdata \
  libyaml-dev \
  pkg-config \
  zip unzip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The app source and the bundle are mounted at runtime by the compose file
# (compose.engine.yml adds an engine checkout); the entrypoint bundles on first boot.
ENTRYPOINT ["./bin/docker-entrypoint"]

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
