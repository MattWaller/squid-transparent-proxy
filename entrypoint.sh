#!/bin/bash
set -e

mkdir -p /var/log/squid
chmod -R 755 /var/log/squid
chown -R proxy:proxy /var/log/squid

SQUID_USER=${SQUID_USER}
SQUID_PASS=${SQUID_PASS}

STARTING_PORT=${STARTING_PORT}
ENDING_PORT=${ENDING_PORT}

THREADS="`expr ${ENDING_PORT} - ${STARTING_PORT}`"

# Create a username/password for ncsa_auth.
htpasswd -c -i -b /etc/squid/.htpasswd ${SQUID_USER} ${SQUID_PASS}
# add basic auth
sed -i "1 i\\
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/.htpasswd\\
auth_param basic children 5\\
auth_param basic realm Squid proxy-caching web server\\
auth_param basic credentialsttl 2 hours\\
auth_param basic casesensitive off" /etc/squid/squid.conf

sed -i "/http_access deny all/ i\\
acl ncsa_users proxy_auth REQUIRED\\
http_access allow ncsa_users" /etc/squid/squid.conf

# Defining Access Control List (ACL) rule set for local IPs
sed -i "acl localnet src 10.0.0.0/8\\
acl localnet src 172.16.0.0/12\\
acl localnet src 192.168.0.0/16\\
acl localnet src fc00::/7\\      
acl localnet src fe80::/10" /etc/squid/squid.conf

#  Defining ACL SSL port
sed -i "acl SSL_ports port 443\\" /etc/squid/squid.conf

# Defining  some other commonly used ports as Safe ports
sed -i "acl Safe_ports port 80\\
acl Safe_ports port 21\\
acl Safe_ports port 443\\
acl Safe_ports port 70\\
acl Safe_ports port 210\\
acl Safe_ports port 1025-65535\\
acl Safe_ports port 280\\
acl Safe_ports port 488\\
acl Safe_ports port 591\\
acl Safe_ports port 777" /etc/squid/squid.conf

sed -i "acl CONNECT method CONNECT" /etc/squid/squid.conf

# Denying connection which are not to localnet, Safe ports or SSL port
sed -i "http_access deny !Safe_ports\\
http_access deny CONNECT !SSL_ports\\
http_access allow localhost manager\\
http_access deny manager\\
http_access allow localnet\\
http_access allow localhost\\
http_access allow all" /etc/squid/squid.conf


for (( i=0; i < $THREADS; ++i ))
do
sed -i "http_port $STARTING_PORT" /etc/squid/squid.conf
echo "$STARTING_PORT"
STARTING_PORT=`expr 1 + $STARTING_PORT`

done


# Setting Squid port
for (( i=0; i < $THREADS; ++i ))
do
	if [ "${#STARTING_PORT}" == "4" ]
	then	
    	sed -i "http_port `expr 1$STARTING_PORT + $i`" /etc/squid/squid.conf
    else
    	if [ ${STARTING_PORT:0:1} -lt 4  ] 
    	then
    		BASEPORT="`expr ${STARTING_PORT:0:1} + 1`${STARTING_PORT:1}"
    		sed -i "http_port `expr $BASEPORT + $i`" /etc/squid/squid.conf
    	else 
    		echo "Error! staring port too high use only ports in range 0-40000" 
    	fi
	fi
done


# add ACL ports
for (( i=0; i < $THREADS; ++i ))
do
	if [ "${#STARTING_PORT}" == "4" ]
	then	
    	sed -i "acl port_$i localport `expr 1$STARTING_PORT + $i`" /etc/squid/squid.conf
    else
    	if [ ${STARTING_PORT:0:1} -lt 4  ] 
    	then
    		BASEPORT="`expr ${STARTING_PORT:0:1} + 1`${STARTING_PORT:1}"
    		sed -i "acl port_$i localport `expr $BASEPORT + $i`" /etc/squid/squid.conf
    	else 
    		echo "Error! staring port too high use only ports in range 0-40000" 
    	fi
	fi
done



sed -i "via off\\
forwarded_for off" /etc/squid/squid.conf


# These request headers make Proxy connection transparent
sed -i "request_header_access Allow allow all\\
request_header_access Authorization allow all\\
request_header_access WWW-Authenticate allow all\\
request_header_access Proxy-Authorization allow all\\
request_header_access Proxy-Authenticate allow all\\
request_header_access Cache-Control allow all\\
request_header_access Content-Encoding allow all\\
request_header_access Content-Length allow all\\
request_header_access Content-Type allow all\\
request_header_access Date allow all\\
request_header_access Expires allow all\\
request_header_access Host allow all\\
request_header_access If-Modified-Since allow all\\
request_header_access Last-Modified allow all\\
request_header_access Location allow all\\
request_header_access Pragma allow all\\
request_header_access Accept allow all\\
request_header_access Accept-Charset allow all\\
request_header_access Accept-Encoding allow all\\
request_header_access Accept-Language allow all\\
request_header_access Content-Language allow all\\
request_header_access Mime-Version allow all\\
request_header_access Retry-After allow all\\
request_header_access Title allow all\\
request_header_access Connection allow all\\
request_header_access Proxy-Connection allow all\\
request_header_access User-Agent allow all\\
request_header_access Cookie allow all\\
request_header_access All deny all" /etc/squid/squid.conf

sed -i "coredump_dir /var/spool/squid\\
refresh_pattern ^ftp:       1440    20% 10080\\
refresh_pattern ^gopher:    1440    0%  1440\\
refresh_pattern -i (/cgi-bin/|\?) 0 0%  0\\
refresh_pattern (Release|Packages(.gz)*)$      0       20%     2880\\
refresh_pattern .       0   20% 4320" /etc/squid/squid.conf


# cached peer
for (( i=0; i < $THREADS; ++i ))
do
	sed -i "cache_peer 127.0.0.1 parent `expr $STARTING_PORT + $i` 0 name=host_$1 no-query no-digest " /etc/squid/squid.conf
done

  # cache peer access
for (( i=0; i < $THREADS; ++i ))
do
	sed -i "cache_peer_access host_$1 allow port_$1 " /etc/squid/squid.conf
done

  sed -i "never_direct allow all" /etc/squid/squid.conf
else
  sed -i "/http_access deny all/ i http_access allow all" /etc/squid/squid.conf
  sed -i "/http_access deny all/d" /etc/squid/squid.conf
  sed -i "/http_access deny manager/d" /etc/squid/squid.conf
fi

# Allow arguments to be passed to squid.
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$@"
  set --
elif [[ ${1} == squid || ${1} == $(which squid) ]]; then
  EXTRA_ARGS="${@:2}"
  set --
fi

# Default behaviour is to launch squid.
if [[ -z ${1} ]]; then
  echo "Starting squid..."
  exec $(which squid) -f /etc/squid/squid.conf -NYCd 1 ${EXTRA_ARGS}
else
  exec "$@"
fi