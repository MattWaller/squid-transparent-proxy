FROM debian:buster-slim

LABEL maintainer="mattghwaller@gmail.com"

RUN apt-get update
RUN apt install squid3 apache2-utils -y

# Set default conf.
RUN rm /etc/squid/squid.conf


ADD entrypoint.sh /sbin/entrypoint.sh
RUN chmod +x /sbin/entrypoint.sh


ENTRYPOINT ["/sbin/entrypoint.sh"]
