#! /usr/bin/env bash
set -e # exit on error

# ENV
export POSTMASTER_EMAIL

echo "POSTMASTER_EMAIL .... ${POSTMASTER_EMAIL}"
echo "FQDN ....             ${FQDN}"

if [ -z "${FQDN}" ]; then
  echo "[ERROR] FQDN must be configured"
  exit 1
fi
if [ -z "${POSTMASTER_EMAIL}" ]; then
  echo "[ERROR] POSTMASTER_EMAIL must be configured"
  exit 1
fi

[ ! -d /config ] && ( echo "No /config directory. Aborting"; exit 1)

# Check if configuration files exists
for file in dovecot-passwd mailserver-cert.pem mailserver-key.pem opendkim-keytable opendkim-signingtable opendkim-trustedhosts postfix-aliases.db postfix-controlled-envelope-senders.db postfix-domains
do
  [ ! -e /config/$file ] && ( echo "No /config/$file file. Aborting"; exit 1)
done

sed -i "s/{{POSTMASTER_EMAIL}}/${POSTMASTER_EMAIL}/" /etc/dovecot/dovecot.conf
chmod +w /var/mail
chown 1000:1000 /var/mail

echo $FQDN >/etc/mailname

sed -i "s/{{FQDN}}/${FQDN}/" /etc/opendkim/opendkim.conf
mkdir -p /config/keys
chown -R opendkim:opendkim /config/keys/

sed -i "s/{{FQDN}}/${FQDN}/" /etc/opendmarc/opendmarc.conf

sed -i "s/{{FQDN}}/${FQDN}/" /etc/amavis/conf.d/50-user

chown postfix:postfix /etc/dovecot/sieve/dovecot.sieve /etc/dovecot/sieve

sievec /etc/dovecot/sieve/dovecot.sieve

mkdir -p /var/run/clamav && chown clamav:clamav /var/run/clamav
mkdir -p /var/lib/clamav && chown -R clamav:clamav /var/lib/clamav

/usr/bin/freshclam --quiet --config-file=/etc/clamav/freshclam.conf
sed -i "s/LogSyslog false/LogSyslog true/" /etc/clamav/freshclam.conf
sed -i "s/Foreground false/Foreground true/" /etc/clamav/freshclam.conf
sed -i "s/POSTGREY_OPTS=\"--inet=10023\"/POSTGREY_OPTS=\"--inet=10023 --delay=60\"/" /etc/default/postgrey

usermod -a -G clamav amavis
usermod -a -G amavis clamav

chown postgrey:postgrey /var/lib/postgrey/
chown -R opendkim:opendkim /config/keys

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
