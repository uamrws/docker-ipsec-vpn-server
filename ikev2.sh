#!/bin/bash
#
# IKEv2 EAP-MSCHAPv2 helper for the strongSwan-based IPsec VPN image.
#
# Derivative of https://github.com/hwdsl2/docker-ipsec-vpn-server
# Copyright (C) 2016-2026 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/

set -euo pipefail

users_file=/etc/ipsec.d/eap-users
id_file=/etc/ipsec.d/ikev2-server-id

usage() {
  cat <<'EOF'
IKEv2 EAP-MSCHAPv2 (strongSwan)

Users are the VPN_USER / VPN_ADDL_USERS accounts from the env file.
Passwords are not stored in this helper. Change them in the env file,
then recreate the container.

Commands:
  ikev2.sh --listclients    List IKEv2 EAP usernames
  ikev2.sh --status         Show server identity and generated files
  ikev2.sh -h               Show this help

Files inside the container:
  /etc/ipsec.d/ca.crt                 CA certificate to install on clients
  /etc/ipsec.d/server.crt             Server certificate
  /etc/ipsec.d/<username>.mobileconfig  Apple VPN profile

Client authentication is EAP-MSCHAPv2: the server uses a certificate,
and the client uses its VPN username and password.
EOF
}

list_clients() {
  if [ ! -s "$users_file" ]; then
    echo "No IKEv2 users found. Mount /etc/ipsec.d and recreate the container." >&2
    exit 1
  fi
  echo "IKEv2 EAP-MSCHAPv2 users:"
  cat "$users_file"
}

show_status() {
  if [ -s "$id_file" ]; then
    echo "IKEv2 server identity: $(cat "$id_file")"
  else
    echo "IKEv2 is not set up. Mount a volume at /etc/ipsec.d and recreate the container."
    exit 1
  fi
  echo "CA certificate: /etc/ipsec.d/ca.crt"
  echo "Server certificate: /etc/ipsec.d/server.crt"
  if command -v swanctl >/dev/null 2>&1 && { [ -S /var/run/charon.vici ] || [ -S /run/charon.vici ]; }; then
    echo
    swanctl --list-conns || true
  fi
}

cmd=${1:-}
case "$cmd" in
  -h|--help|"")
    usage
    ;;
  --listclients)
    list_clients
    ;;
  --status)
    show_status
    ;;
  --addclient|--exportclient|--removeikev2)
    echo "This image uses IKEv2 EAP-MSCHAPv2, not per-client certificates." >&2
    echo "Add users with VPN_ADDL_USERS and VPN_ADDL_PASSWORDS, then recreate the container." >&2
    exit 1
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
