FROM ruby:3.4-alpine

RUN apk add --no-cache --update build-base \
                          linux-headers \
                          bash openssh-client git tar \
                          postgresql-dev \
                          nodejs \
                          tzdata libcurl curl-dev libxml2 libxml2-dev gcc make yaml-dev \
                          sqlite sqlite-dev sqlite-libs \
                          imagemagick \
                          ffmpeg x264 x265 libvpx libtheora \
                          file

ENV APP_PATH /opt/project

# Different layer for gems installation
WORKDIR $APP_PATH
COPY . $APP_PATH
RUN gem install ovirt-engine-sdk -v4.6.0 -- --with-cflags="-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration"
RUN gem install bundler  \
    && bundle config set with 'development test'\
    && git config --global --add safe.directory /opt/project \
    && bundle install --jobs `expr $(cat /proc/cpuinfo | grep -c "cpu cores") - 1` --retry 3
CMD bundle exec rspec spec
