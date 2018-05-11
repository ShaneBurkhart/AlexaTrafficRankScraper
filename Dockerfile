FROM ruby:2.5.0
MAINTAINER Shane Burkhart <shaneburkhart@gmail.com>

RUN mkdir -p /app
WORKDIR /app

RUN mkdir tmp
ADD Gemfile Gemfile
RUN bundle install --without development test
RUN rm -r tmp

ADD . /app

CMD ["bundle", "exec", "ruby", "main.rb"]
