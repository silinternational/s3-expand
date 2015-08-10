FROM ubuntu:latest
MAINTAINER <Peter Kohler> "peter_kohler@sil.org"

RUN apt-get update && apt-get install -y \
  s3cmd

COPY . /data
WORKDIR /data/tests

ENTRYPOINT ["./run-tests.sh"]
