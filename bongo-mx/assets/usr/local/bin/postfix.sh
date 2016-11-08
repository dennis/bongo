#! /usr/bin/env bash
set -eu

trap "{ echo Stopping postfix; /usr/sbin/postfix stop; exit 0; }" EXIT

echo "Starting postfix for $(hostname)"

postconf myhostname=$(hostname)
postconf mydestination="$(hostname), localhost.localdomain, localhost"

cp -f /etc/services /var/spool/postfix/etc/services
cp -f /etc/hosts /var/spool/postfix/etc/hosts
cp -f /etc/localtime /var/spool/postfix/etc/localtime
cp -f /etc/resolv.conf /var/spool/postfix/etc/resolv.conf

#chmod 0644 /etc/postfix/header_checks
#chmod 0644 /etc/postfix/main.cf
#chmod 0644 /etc/postfix/master.cf


/usr/sbin/postfix -c /etc/postfix start

sleep infinity

