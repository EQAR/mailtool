#!/bin/sh
#
# entrypoint.sh - create configuration file from environment variables
#

# configuration defaults (because envsubst doesn't support default values)
set -a
SMTP_FROM="${SMTP_FROM:-docker@example.com}"
SMTP_PORT="${SMTP_PORT:-587}"
set +a

# generate configs
echo -n "Generating /etc/msmtprc: "
envsubst < /usr/local/share/etc-templates/msmtprc > /etc/msmtprc
chmod 0600 /etc/msmtprc
echo "Done."

exec "$@"
