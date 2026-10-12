#!/bin/bash
#
# Docker script to configure and start an IPsec VPN server
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC! THIS IS ONLY MEANT TO BE RUN
# IN A CONTAINER!
#
# This file is part of IPsec VPN Docker image, available at:
# https://github.com/hwdsl2/docker-ipsec-vpn-server
#
# Copyright (C) 2016-2026 Lin Song <linsongui@gmail.com>
# Based on the work of Thomas Sarlandie (Copyright 2012)
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
nospaces() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
onespace() { printf '%s' "$1" | tr -s ' '; }
noquotes() { printf '%s' "$1" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }
noquotes2() { printf '%s' "$1" | sed -e 's/" "/ /g' -e "s/' '/ /g"; }

ip2int() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  printf '%s\n' $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

ip_in_cidr() {
  local ip_i base_i bits mask_i
  ip_i=$(ip2int "$1")
  base_i=$(ip2int "${2%/*}")
  bits=${2#*/}
  if [ "$bits" -eq 0 ]; then
    return 0
  fi
  mask_i=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
  [ $((ip_i & mask_i)) -eq $((base_i & mask_i)) ]
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

have_plugin() {
  local name=$1 dir f glob
  glob=$(shopt -p nullglob)
  shopt -s nullglob
  for dir in /usr/lib/ipsec/plugins /usr/libexec/ipsec/plugins /usr/lib/strongswan/plugins; do
    for f in "$dir"/*"$name"*.so; do
      eval "$glob"
      return 0
    done
  done
  eval "$glob"
  return 1
}

write_mobileconfig() {
  local user=$1 pass=$2 outfile=$3 include_pass=$4
  local uuid_root uuid_ca uuid_vpn display
  uuid_root=$(new_uuid)
  uuid_ca=$(new_uuid)
  uuid_vpn=$(new_uuid)
  display=${VPN_CLIENT_NAME:-IKEv2 VPN}
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '%s\n' '  <key>PayloadDisplayName</key>'
    printf '%s\n' "  <string>$(xml_escape "$display")</string>"
    printf '%s\n' '  <key>PayloadIdentifier</key>'
    printf '%s\n' "  <string>com.strongswan.ikev2.$(xml_escape "$user")</string>"
    printf '%s\n' '  <key>PayloadType</key>'
    printf '%s\n' '  <string>Configuration</string>'
    printf '%s\n' '  <key>PayloadUUID</key>'
    printf '%s\n' "  <string>$uuid_root</string>"
    printf '%s\n' '  <key>PayloadVersion</key>'
    printf '%s\n' '  <integer>1</integer>'
    printf '%s\n' '  <key>PayloadContent</key>'
    printf '%s\n' '  <array>'
    printf '%s\n' '    <dict>'
    printf '%s\n' '      <key>PayloadType</key>'
    printf '%s\n' '      <string>com.apple.security.root</string>'
    printf '%s\n' '      <key>PayloadIdentifier</key>'
    printf '%s\n' "      <string>com.strongswan.ikev2.ca.$(xml_escape "$user")</string>"
    printf '%s\n' '      <key>PayloadUUID</key>'
    printf '%s\n' "      <string>$uuid_ca</string>"
    printf '%s\n' '      <key>PayloadVersion</key>'
    printf '%s\n' '      <integer>1</integer>'
    printf '%s\n' '      <key>PayloadDisplayName</key>'
    printf '%s\n' '      <string>IKEv2 VPN CA</string>'
    printf '%s\n' '      <key>PayloadCertificateFileName</key>'
    printf '%s\n' '      <string>ca.crt</string>'
    printf '%s\n' '      <key>PayloadContent</key>'
    printf '%s\n' '      <data>'
    openssl x509 -in "$CA_CRT" -outform der | openssl base64
    printf '%s\n' '      </data>'
    printf '%s\n' '    </dict>'
    printf '%s\n' '    <dict>'
    printf '%s\n' '      <key>PayloadType</key>'
    printf '%s\n' '      <string>com.apple.vpn.managed</string>'
    printf '%s\n' '      <key>PayloadIdentifier</key>'
    printf '%s\n' "      <string>com.strongswan.ikev2.vpn.$(xml_escape "$user")</string>"
    printf '%s\n' '      <key>PayloadUUID</key>'
    printf '%s\n' "      <string>$uuid_vpn</string>"
    printf '%s\n' '      <key>PayloadVersion</key>'
    printf '%s\n' '      <integer>1</integer>'
    printf '%s\n' '      <key>PayloadDisplayName</key>'
    printf '%s\n' "      <string>$(xml_escape "$display")</string>"
    printf '%s\n' '      <key>UserDefinedName</key>'
    printf '%s\n' "      <string>$(xml_escape "$display")</string>"
    printf '%s\n' '      <key>VPNType</key>'
    printf '%s\n' '      <string>IKEv2</string>'
    printf '%s\n' '      <key>IKEv2</key>'
    printf '%s\n' '      <dict>'
    printf '%s\n' '        <key>RemoteAddress</key>'
    printf '%s\n' "        <string>$(xml_escape "$server_addr")</string>"
    printf '%s\n' '        <key>RemoteIdentifier</key>'
    printf '%s\n' "        <string>$(xml_escape "$server_addr")</string>"
    printf '%s\n' '        <key>LocalIdentifier</key>'
    printf '%s\n' "        <string>$(xml_escape "$user")</string>"
    printf '%s\n' '        <key>AuthenticationMethod</key>'
    printf '%s\n' '        <string>None</string>'
    printf '%s\n' '        <key>ExtendedAuthEnabled</key>'
    printf '%s\n' '        <integer>1</integer>'
    printf '%s\n' '        <key>AuthName</key>'
    printf '%s\n' "        <string>$(xml_escape "$user")</string>"
    if [ "$include_pass" = yes ]; then
      printf '%s\n' '        <key>AuthPassword</key>'
      printf '%s\n' "        <string>$(xml_escape "$pass")</string>"
    fi
    printf '%s\n' '        <key>DeadPeerDetectionRate</key>'
    printf '%s\n' '        <string>Medium</string>'
    printf '%s\n' '        <key>DisableMOBIKE</key>'
    printf '%s\n' '        <integer>0</integer>'
    printf '%s\n' '        <key>EnablePFS</key>'
    printf '%s\n' '        <integer>0</integer>'
    printf '%s\n' '        <key>IKESecurityAssociationParameters</key>'
    printf '%s\n' '        <dict>'
    printf '%s\n' '          <key>EncryptionAlgorithm</key>'
    printf '%s\n' '          <string>AES-256</string>'
    printf '%s\n' '          <key>IntegrityAlgorithm</key>'
    printf '%s\n' '          <string>SHA2-256</string>'
    printf '%s\n' '          <key>DiffieHellmanGroup</key>'
    printf '%s\n' '          <integer>14</integer>'
    printf '%s\n' '        </dict>'
    printf '%s\n' '        <key>ChildSecurityAssociationParameters</key>'
    printf '%s\n' '        <dict>'
    printf '%s\n' '          <key>EncryptionAlgorithm</key>'
    printf '%s\n' '          <string>AES-256</string>'
    printf '%s\n' '          <key>IntegrityAlgorithm</key>'
    printf '%s\n' '          <string>SHA2-256</string>'
    printf '%s\n' '          <key>DiffieHellmanGroup</key>'
    printf '%s\n' '          <integer>14</integer>'
    printf '%s\n' '        </dict>'
    printf '%s\n' '      </dict>'
    printf '%s\n' '    </dict>'
    printf '%s\n' '  </array>'
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
  } > "$outfile"
  chmod 600 "$outfile"
}

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

get_public_ip() {
  local ip_addr ip_url
  for ip_url in https://ipv4.icanhazip.com https://api.ipify.org; do
    ip_addr=$(wget -t 2 -T 10 -4 --max-redirect=0 -qO- "$ip_url" 2>/dev/null) || continue
    ip_addr=${ip_addr%$'\r'}
    [[ "$ip_addr" != *$'\n'* && "$ip_addr" != *$'\r'* ]] || continue
    if check_ip "$ip_addr"; then
      public_ip="$ip_addr"
      return 0
    fi
  done
  return 1
}

check_ip6() {
  IP6_REGEX='^[0-9a-fA-F]{0,4}(:[0-9a-fA-F]{0,4}){1,7}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP6_REGEX"
}

check_cidr() {
  CIDR_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/(3[0-2]|[1-2][0-9]|[0-9]))$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$CIDR_REGEX"
}

check_dns_name() {
  FQDN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$FQDN_REGEX"
}

check_client_name() {
  ! { [ "${#1}" -gt "64" ] || printf '%s' "$1" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+' \
    || case $1 in -*) true ;; *) false ;; esac; }
}

if [ ! -f "/.dockerenv" ] && [ ! -f "/run/.containerenv" ] \
  && [ -z "$KUBERNETES_SERVICE_HOST" ] \
  && ! head -n 1 /proc/1/sched 2>/dev/null | grep -q '^run\.sh '; then
  exiterr "This script ONLY runs in a container (e.g. Docker, Podman)."
fi

if ip link add dummy0 type dummy 2>&1 | grep -q "not permitted"; then
cat 1>&2 <<'EOF'
Error: This Docker image should be run in privileged mode.
       See: https://github.com/hwdsl2/docker-ipsec-vpn-server

EOF
  exit 1
fi
ip link delete dummy0 >/dev/null 2>&1

os_type=debian
os_arch=$(uname -m | tr -dc 'A-Za-z0-9_-')
[ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")

if [ ! -e /dev/ppp ]; then
cat <<'EOF'

Warning: /dev/ppp is missing, and IPsec/L2TP mode may not work.
         Please use IKEv2 or IPsec/XAuth mode to connect.
         Debian 11/10 users, see https://vpnsetup.net/debian10
EOF
fi

NET_IFACE=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
[ -z "$NET_IFACE" ] && NET_IFACE=$(ip -4 route list 0/0 2>/dev/null | grep -m 1 -Po '(?<=dev )(\S+)')
[ -z "$NET_IFACE" ] && NET_IFACE=eth0

mkdir -p /opt/src
vpn_env="/opt/src/vpn.env"
vpn_env_dir="/opt/src/env/vpn.env"
if [ -f "$vpn_env_dir" ]; then
  vpn_env="$vpn_env_dir"
fi
vpn_gen_env="/etc/ipsec.d/vpn-gen.env"
if [ -z "$VPN_IPSEC_PSK" ] && [ -z "$VPN_USER" ] && [ -z "$VPN_PASSWORD" ]; then
  if [ -f "$vpn_env" ]; then
    echo
    echo 'Retrieving VPN credentials...'
    . "$vpn_env"
  elif [ -f "$vpn_gen_env" ]; then
    echo
    echo 'Retrieving previously generated VPN credentials...'
    . "$vpn_gen_env"
  else
    echo
    echo 'VPN credentials not set by user. Generating random PSK and password...'
    VPN_IPSEC_PSK=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' </dev/urandom 2>/dev/null | head -c 20)
    VPN_USER=vpnuser
    VPN_PASSWORD=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' </dev/urandom 2>/dev/null | head -c 16)
    printf '%s\n' "VPN_IPSEC_PSK='$VPN_IPSEC_PSK'" > "$vpn_gen_env"
    printf '%s\n' "VPN_USER='$VPN_USER'" >> "$vpn_gen_env"
    printf '%s\n' "VPN_PASSWORD='$VPN_PASSWORD'" >> "$vpn_gen_env"
    chmod 600 "$vpn_gen_env"
  fi
fi

# Remove whitespace and quotes around VPN variables, if any
VPN_IPSEC_PSK=$(nospaces "$VPN_IPSEC_PSK")
VPN_IPSEC_PSK=$(noquotes "$VPN_IPSEC_PSK")
VPN_USER=$(nospaces "$VPN_USER")
VPN_USER=$(noquotes "$VPN_USER")
VPN_PASSWORD=$(nospaces "$VPN_PASSWORD")
VPN_PASSWORD=$(noquotes "$VPN_PASSWORD")
if [ -n "$VPN_ADDL_USERS" ] && [ -n "$VPN_ADDL_PASSWORDS" ]; then
  VPN_ADDL_USERS=$(nospaces "$VPN_ADDL_USERS")
  VPN_ADDL_USERS=$(noquotes "$VPN_ADDL_USERS")
  VPN_ADDL_USERS=$(onespace "$VPN_ADDL_USERS")
  VPN_ADDL_USERS=$(noquotes2 "$VPN_ADDL_USERS")
  VPN_ADDL_PASSWORDS=$(nospaces "$VPN_ADDL_PASSWORDS")
  VPN_ADDL_PASSWORDS=$(noquotes "$VPN_ADDL_PASSWORDS")
  VPN_ADDL_PASSWORDS=$(onespace "$VPN_ADDL_PASSWORDS")
  VPN_ADDL_PASSWORDS=$(noquotes2 "$VPN_ADDL_PASSWORDS")
  if [ -n "$VPN_ADDL_IP_ADDRS" ]; then
    VPN_ADDL_IP_ADDRS=$(nospaces "$VPN_ADDL_IP_ADDRS")
    VPN_ADDL_IP_ADDRS=$(noquotes "$VPN_ADDL_IP_ADDRS")
    VPN_ADDL_IP_ADDRS=$(onespace "$VPN_ADDL_IP_ADDRS")
    VPN_ADDL_IP_ADDRS=$(noquotes2 "$VPN_ADDL_IP_ADDRS")
  fi
else
  VPN_ADDL_USERS=""
  VPN_ADDL_PASSWORDS=""
  VPN_ADDL_IP_ADDRS=""
fi
if [ -n "$VPN_DNS_SRV1" ]; then
  VPN_DNS_SRV1=$(nospaces "$VPN_DNS_SRV1")
  VPN_DNS_SRV1=$(noquotes "$VPN_DNS_SRV1")
fi
if [ -n "$VPN_DNS_SRV2" ]; then
  VPN_DNS_SRV2=$(nospaces "$VPN_DNS_SRV2")
  VPN_DNS_SRV2=$(noquotes "$VPN_DNS_SRV2")
fi
if [ -n "$VPN_CLIENT_NAME" ]; then
  VPN_CLIENT_NAME=$(nospaces "$VPN_CLIENT_NAME")
  VPN_CLIENT_NAME=$(noquotes "$VPN_CLIENT_NAME")
fi
if [ -n "$VPN_DNS_NAME" ]; then
  VPN_DNS_NAME=$(nospaces "$VPN_DNS_NAME")
  VPN_DNS_NAME=$(noquotes "$VPN_DNS_NAME")
fi
if [ -n "$VPN_PUBLIC_IP" ]; then
  VPN_PUBLIC_IP=$(nospaces "$VPN_PUBLIC_IP")
  VPN_PUBLIC_IP=$(noquotes "$VPN_PUBLIC_IP")
fi
if [ -n "$VPN_ANDROID_MTU_FIX" ]; then
  VPN_ANDROID_MTU_FIX=$(nospaces "$VPN_ANDROID_MTU_FIX")
  VPN_ANDROID_MTU_FIX=$(noquotes "$VPN_ANDROID_MTU_FIX")
fi
if [ -n "$VPN_SHA2_TRUNCBUG" ]; then
  VPN_SHA2_TRUNCBUG=$(nospaces "$VPN_SHA2_TRUNCBUG")
  VPN_SHA2_TRUNCBUG=$(noquotes "$VPN_SHA2_TRUNCBUG")
fi
if [ -n "$VPN_CLIENT_VALIDITY" ]; then
  VPN_CLIENT_VALIDITY=$(nospaces "$VPN_CLIENT_VALIDITY")
  VPN_CLIENT_VALIDITY=$(noquotes "$VPN_CLIENT_VALIDITY")
fi
if [ -n "$VPN_PROTECT_CONFIG" ]; then
  VPN_PROTECT_CONFIG=$(nospaces "$VPN_PROTECT_CONFIG")
  VPN_PROTECT_CONFIG=$(noquotes "$VPN_PROTECT_CONFIG")
fi
if [ -n "$VPN_SPLIT_IKEV2" ]; then
  VPN_SPLIT_IKEV2=$(nospaces "$VPN_SPLIT_IKEV2")
  VPN_SPLIT_IKEV2=$(noquotes "$VPN_SPLIT_IKEV2")
fi
if [ -n "$VPN_DISABLE_IPSEC_L2TP" ]; then
  VPN_DISABLE_IPSEC_L2TP=$(nospaces "$VPN_DISABLE_IPSEC_L2TP")
  VPN_DISABLE_IPSEC_L2TP=$(noquotes "$VPN_DISABLE_IPSEC_L2TP")
fi
if [ -n "$VPN_DISABLE_IPSEC_XAUTH" ]; then
  VPN_DISABLE_IPSEC_XAUTH=$(nospaces "$VPN_DISABLE_IPSEC_XAUTH")
  VPN_DISABLE_IPSEC_XAUTH=$(noquotes "$VPN_DISABLE_IPSEC_XAUTH")
fi
if [ -n "$VPN_IKEV2_ONLY" ]; then
  VPN_IKEV2_ONLY=$(nospaces "$VPN_IKEV2_ONLY")
  VPN_IKEV2_ONLY=$(noquotes "$VPN_IKEV2_ONLY")
fi
if [ -n "$VPN_ENABLE_MODP1024" ]; then
  VPN_ENABLE_MODP1024=$(nospaces "$VPN_ENABLE_MODP1024")
  VPN_ENABLE_MODP1024=$(noquotes "$VPN_ENABLE_MODP1024")
fi
case $VPN_ENABLE_MODP1024 in
  [yY][eE][sS])
    echo "Warning: VPN_ENABLE_MODP1024 is no longer supported and will be ignored." >&2
    echo "         Remove it from your 'env' file and use IKEv2 for affected Android clients." >&2
    ;;
esac
if [ -n "$VPN_ENABLE_MODP1536" ]; then
  VPN_ENABLE_MODP1536=$(nospaces "$VPN_ENABLE_MODP1536")
  VPN_ENABLE_MODP1536=$(noquotes "$VPN_ENABLE_MODP1536")
fi
if [ -n "$VPN_L2TP_NET" ]; then
  VPN_L2TP_NET=$(nospaces "$VPN_L2TP_NET")
  VPN_L2TP_NET=$(noquotes "$VPN_L2TP_NET")
fi
if [ -n "$VPN_L2TP_LOCAL" ]; then
  VPN_L2TP_LOCAL=$(nospaces "$VPN_L2TP_LOCAL")
  VPN_L2TP_LOCAL=$(noquotes "$VPN_L2TP_LOCAL")
fi
if [ -n "$VPN_L2TP_POOL" ]; then
  VPN_L2TP_POOL=$(nospaces "$VPN_L2TP_POOL")
  VPN_L2TP_POOL=$(noquotes "$VPN_L2TP_POOL")
fi
if [ -n "$VPN_XAUTH_NET" ]; then
  VPN_XAUTH_NET=$(nospaces "$VPN_XAUTH_NET")
  VPN_XAUTH_NET=$(noquotes "$VPN_XAUTH_NET")
fi
if [ -n "$VPN_XAUTH_POOL" ]; then
  VPN_XAUTH_POOL=$(nospaces "$VPN_XAUTH_POOL")
  VPN_XAUTH_POOL=$(noquotes "$VPN_XAUTH_POOL")
fi
if [ -n "$VPN_PUBLIC_IP6" ]; then
  VPN_PUBLIC_IP6=$(nospaces "$VPN_PUBLIC_IP6")
  VPN_PUBLIC_IP6=$(noquotes "$VPN_PUBLIC_IP6")
fi
if [ -n "$VPN_IP6_NET" ]; then
  VPN_IP6_NET=$(nospaces "$VPN_IP6_NET")
  VPN_IP6_NET=$(noquotes "$VPN_IP6_NET")
fi
if [ -n "$VPN_IKEV2_NET" ]; then
  VPN_IKEV2_NET=$(nospaces "$VPN_IKEV2_NET")
  VPN_IKEV2_NET=$(noquotes "$VPN_IKEV2_NET")
fi
if [ -n "$VPN_IKEV2_POOL" ]; then
  VPN_IKEV2_POOL=$(nospaces "$VPN_IKEV2_POOL")
  VPN_IKEV2_POOL=$(noquotes "$VPN_IKEV2_POOL")
fi

ip6=""
if [ -n "$VPN_PUBLIC_IP6" ]; then
  ip6="$VPN_PUBLIC_IP6"
  check_ip6 "$ip6" || { echo "Warning: Invalid IPv6 address in 'VPN_PUBLIC_IP6'. Detecting IPv6..." >&2; ip6=""; }
fi
if [ -z "$ip6" ]; then
  ip6=$(ip -6 addr 2>/dev/null | awk '/inet6 [23]/ {print $2}' | cut -d'/' -f1 | head -n1)
  check_ip6 "$ip6" || ip6=""
  if [ -z "$ip6" ] && ip -6 addr 2>/dev/null | grep 'inet6' | grep -qv 'inet6 \(::1\|fe80\)'; then
    ip6=$(wget -t 2 -T 10 -qO- https://ipv6.icanhazip.com 2>/dev/null)
    check_ip6 "$ip6" || ip6=""
  fi
fi

if [ -z "$VPN_IPSEC_PSK" ] || [ -z "$VPN_USER" ] || [ -z "$VPN_PASSWORD" ]; then
  exiterr "All VPN credentials must be specified. Edit your 'env' file and re-enter them."
fi
if printf '%s' "$VPN_IPSEC_PSK $VPN_USER $VPN_PASSWORD $VPN_ADDL_USERS $VPN_ADDL_PASSWORDS" | LC_ALL=C grep -q '[^ -~]\+'; then
  exiterr "VPN credentials must not contain non-ASCII characters."
fi
case "$VPN_IPSEC_PSK $VPN_USER $VPN_PASSWORD $VPN_ADDL_USERS $VPN_ADDL_PASSWORDS" in
  *[\\\"\']*)
    exiterr "VPN credentials must not contain these special characters: \\ \" '"
    ;;
esac
if printf '%s' "$VPN_USER $VPN_ADDL_USERS" | tr ' ' '\n' | sort | uniq -c | grep -qv '^ *1 '; then
  exiterr "VPN usernames must not contain duplicates."
fi

# Check DNS servers and try to resolve hostnames to IPs
if [ -n "$VPN_DNS_SRV1" ]; then
  check_ip "$VPN_DNS_SRV1" || VPN_DNS_SRV1=$(dig -t A -4 +short "$VPN_DNS_SRV1")
  if ! check_ip "$VPN_DNS_SRV1"; then
cat <<'EOF'

Warning: Invalid DNS server. Check VPN_DNS_SRV1 in your 'env' file.
EOF
    VPN_DNS_SRV1=""
  fi
fi
if [ -n "$VPN_DNS_SRV2" ]; then
  check_ip "$VPN_DNS_SRV2" || VPN_DNS_SRV2=$(dig -t A -4 +short "$VPN_DNS_SRV2")
  if ! check_ip "$VPN_DNS_SRV2"; then
cat <<'EOF'

Warning: Invalid DNS server. Check VPN_DNS_SRV2 in your 'env' file.
EOF
    VPN_DNS_SRV2=""
  fi
fi
if [ -n "$VPN_CLIENT_NAME" ]; then
  if ! check_client_name "$VPN_CLIENT_NAME"; then
cat <<'EOF'

Warning: Invalid client name. Use one word only, no special characters except '-' and '_'.
         Falling back to default client name 'vpnclient'.
EOF
    VPN_CLIENT_NAME=""
  fi
fi
if [ -n "$VPN_DNS_NAME" ]; then
  if ! check_dns_name "$VPN_DNS_NAME"; then
cat <<'EOF'

Warning: Invalid DNS name. 'VPN_DNS_NAME' must be a fully qualified domain name (FQDN).
         Falling back to using this server's IP address.
EOF
    VPN_DNS_NAME=""
  fi
fi
if [ -n "$VPN_SPLIT_IKEV2" ]; then
  if ! check_cidr "$VPN_SPLIT_IKEV2"; then
cat <<'EOF'

Warning: Invalid split VPN subnet. Check VPN_SPLIT_IKEV2 in your 'env' file.
EOF
    VPN_SPLIT_IKEV2=""
  fi
fi

echo
echo 'Trying to auto discover IP of this server...'
# In case auto IP discovery fails, manually define the public IP
# of this server in your 'env' file, as variable 'VPN_PUBLIC_IP'.
public_ip=${VPN_PUBLIC_IP:-''}
check_ip "$public_ip" || get_public_ip \
  || exiterr "Cannot detect this server's public IP. Define it in your 'env' file as 'VPN_PUBLIC_IP'."

if [ -n "$VPN_DNS_NAME" ]; then
  server_addr="$VPN_DNS_NAME"
else
  server_addr="$public_ip"
fi

L2TP_NET=${VPN_L2TP_NET:-'192.168.42.0/24'}
L2TP_LOCAL=${VPN_L2TP_LOCAL:-'192.168.42.1'}
L2TP_POOL=${VPN_L2TP_POOL:-'192.168.42.10-192.168.42.250'}
XAUTH_NET=${VPN_XAUTH_NET:-'192.168.43.0/24'}
XAUTH_POOL=${VPN_XAUTH_POOL:-'192.168.43.10-192.168.43.250'}
IKEV2_NET=${VPN_IKEV2_NET:-'192.168.44.0/24'}
IKEV2_POOL=${VPN_IKEV2_POOL:-'192.168.44.10-192.168.44.250'}
IP6_NET=${VPN_IP6_NET:-'fddd:500:500:500::/64'}
DNS_SRV1=${VPN_DNS_SRV1:-'8.8.8.8'}
DNS_SRV2=${VPN_DNS_SRV2:-'8.8.4.4'}
DNS_SRVS="\"$DNS_SRV1 $DNS_SRV2\""
[ -n "$VPN_DNS_SRV1" ] && [ -z "$VPN_DNS_SRV2" ] && DNS_SRVS="$DNS_SRV1"
vp_ip6=""
[ -n "$ip6" ] && vp_ip6=",%v6:fc00::/7,%v6:!$IP6_NET"

if [ -n "$VPN_DNS_SRV1" ] && [ -n "$VPN_DNS_SRV2" ]; then
  echo
  echo "Setting DNS servers to $VPN_DNS_SRV1 and $VPN_DNS_SRV2..."
elif [ -n "$VPN_DNS_SRV1" ]; then
  echo
  echo "Setting DNS server to $VPN_DNS_SRV1..."
fi

sha2_truncbug=no
case $VPN_SHA2_TRUNCBUG in
  [yY][eE][sS])
    echo
    echo "Enabling the SHA-2 truncation workaround in strongSwan..."
    sha2_truncbug=yes
    ;;
esac
disable_ipsec_l2tp=no
case $VPN_DISABLE_IPSEC_L2TP in
  [yY][eE][sS])
    disable_ipsec_l2tp=yes
    ;;
esac
disable_ipsec_xauth=no
case $VPN_DISABLE_IPSEC_XAUTH in
  [yY][eE][sS])
    disable_ipsec_xauth=yes
    ;;
esac
case $VPN_IKEV2_ONLY in
  [yY][eE][sS])
    disable_ipsec_l2tp=yes
    disable_ipsec_xauth=yes
    ;;
esac
ike_proposals="aes256-sha256-modp2048,aes128-sha256-modp2048,aes256-sha1-modp2048,aes128-sha1-modp2048"
case $VPN_ENABLE_MODP1536 in
  [yY][eE][sS])
    echo
    echo "Adding modp1536 to the IKEv1 proposals..."
    ike_proposals="${ike_proposals},aes256-sha256-modp1536,aes128-sha1-modp1536"
    ;;
esac
esp_proposals="aes256gcm16,aes128gcm16,aes256-sha256,aes128-sha256,aes256-sha1,aes128-sha1"
ikev2_proposals="aes256gcm16-prfsha256-ecp256,aes128gcm16-prfsha256-ecp256,aes256gcm16-prfsha256-modp2048,aes128gcm16-prfsha256-modp2048,aes256-sha256-modp2048,aes128-sha256-modp2048"
ikev2_esp="aes256gcm16,aes128gcm16,aes256-sha256,aes128-sha256"

if [ "$disable_ipsec_l2tp" = yes ] && [ "$disable_ipsec_xauth" = yes ]; then
cat <<'EOF'

Note: Running in IKEv2-only mode via env file option.
      IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes are disabled.
EOF
  if ! grep -q " /etc/ipsec.d " /proc/mounts; then
cat <<'EOF'

Warning: /etc/ipsec.d not mounted. IKEv2 setup requires a Docker volume
         mounted at /etc/ipsec.d.
EOF
  fi
elif [ "$disable_ipsec_l2tp" = yes ]; then
cat <<'EOF'

Note: IPsec/L2TP mode is disabled via env file option.
EOF
elif [ "$disable_ipsec_xauth" = yes ]; then
cat <<'EOF'

Note: IPsec/XAuth ("Cisco IPsec") mode is disabled via env file option.
EOF
fi

if ! check_cidr "$IKEV2_NET"; then
  echo "Warning: Invalid VPN_IKEV2_NET. Using 192.168.44.0/24." >&2
  IKEV2_NET='192.168.44.0/24'
fi
if ! printf '%s' "$IKEV2_POOL" | grep -Eq '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])-(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'; then
  echo "Warning: Invalid VPN_IKEV2_POOL. Using 192.168.44.10-192.168.44.250." >&2
  IKEV2_POOL='192.168.44.10-192.168.44.250'
fi
pool_first=${IKEV2_POOL%%-*}
if ! ip_in_cidr "$pool_first" "$IKEV2_NET"; then
  echo "Warning: VPN_IKEV2_POOL is outside VPN_IKEV2_NET. IKEv2 client NAT may fail." >&2
fi

if [ -n "$VPN_DNS_SRV1" ] && [ -z "$VPN_DNS_SRV2" ]; then
  dns_list=$DNS_SRV1
else
  dns_list="$DNS_SRV1, $DNS_SRV2"
fi
ikev2_ts="0.0.0.0/0"
if [ -n "$VPN_SPLIT_IKEV2" ]; then
  ikev2_ts=$VPN_SPLIT_IKEV2
elif [ -n "$ip6" ]; then
  ikev2_ts="0.0.0.0/0, ::/0"
fi
ikev2_addrs=$IKEV2_POOL
if [ -n "$ip6" ]; then
  ip6_base=${IP6_NET%/*}
  ikev2_addrs="$IKEV2_POOL, ${ip6_base}10-${ip6_base}fe"
fi

ikev2_enabled=no
mkdir -p /etc/ipsec.d
if grep -q " /etc/ipsec.d " /proc/mounts; then
  if have_plugin eap-mschapv2 && have_plugin eap-identity; then
    ikev2_enabled=yes
  else
    echo "Warning: strongSwan EAP-MSCHAPv2 plugins are missing. IKEv2 is disabled." >&2
  fi
else
  echo
  echo "Warning: /etc/ipsec.d is not a mounted volume, so IKEv2 EAP-MSCHAPv2 is not enabled."
  echo "         Mount a Docker volume at /etc/ipsec.d to keep the CA and server certificate."
fi
if [ "$disable_ipsec_xauth" != yes ] && ! have_plugin xauth-generic; then
  echo "Warning: strongSwan xauth-generic plugin is missing. Cisco IPsec is disabled." >&2
  disable_ipsec_xauth=yes
fi

SWAN_DIR=/etc/ipsec.d/swanctl
CA_KEY=/etc/ipsec.d/private/ca.key
CA_CRT="$SWAN_DIR/x509ca/ca.crt"
CA_SRL=/etc/ipsec.d/ca.srl
SRV_KEY="$SWAN_DIR/private/server.key"
SRV_CRT="$SWAN_DIR/x509/server.crt"
SRV_CSR="$SWAN_DIR/private/server.csr"
ID_FILE=/etc/ipsec.d/ikev2-server-id
mkdir -p "$SWAN_DIR/x509" "$SWAN_DIR/x509ca" "$SWAN_DIR/x509crl" \
  "$SWAN_DIR/x509ocsp" "$SWAN_DIR/x509aa" "$SWAN_DIR/x509ac" \
  "$SWAN_DIR/private" "$SWAN_DIR/pubkey" "$SWAN_DIR/rsa" "$SWAN_DIR/ecdsa" \
  "$SWAN_DIR/pkcs8" "$SWAN_DIR/pkcs12" "$SWAN_DIR/bliss" /etc/ipsec.d/private
chmod 700 "$SWAN_DIR/private" /etc/ipsec.d/private
if [ -f "$SWAN_DIR/private/ca.key" ] && [ ! -s "$CA_KEY" ]; then
  mv "$SWAN_DIR/private/ca.key" "$CA_KEY"
fi
rm -f "$SWAN_DIR/private/ca.srl"
if [ -d /etc/swanctl ] && [ ! -L /etc/swanctl ]; then
  rm -rf /etc/swanctl
fi
ln -sfn "$SWAN_DIR" /etc/swanctl

include_eap_pass=yes
case $VPN_PROTECT_CONFIG in
  [yY][eE][sS]) include_eap_pass=no ;;
esac

if [ "$ikev2_enabled" = yes ]; then
  if [ ! -s "$CA_KEY" ] || [ ! -s "$CA_CRT" ]; then
    echo
    echo "Generating IKEv2 CA certificate..."
    openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
      -keyout "$CA_KEY" -out "$CA_CRT" \
      -subj "/CN=IKEv2 VPN CA" \
      -addext basicConstraints=critical,CA:TRUE \
      -addext keyUsage=critical,keyCertSign,cRLSign \
      || exiterr "Failed to generate the IKEv2 CA certificate."
  fi
  if [ ! -s "$SRV_KEY" ] || [ ! -s "$SRV_CRT" ] || [ "$(cat "$ID_FILE" 2>/dev/null || true)" != "$server_addr" ]; then
    echo "Generating IKEv2 server certificate for $server_addr..."
    san="IP:${public_ip}"
    if [ -n "$VPN_DNS_NAME" ]; then
      san="DNS:${VPN_DNS_NAME},IP:${public_ip}"
    fi
    openssl req -newkey rsa:3072 -nodes -keyout "$SRV_KEY" -out "$SRV_CSR" \
      -subj "/CN=${server_addr}" \
      || exiterr "Failed to generate the IKEv2 server key."
    openssl x509 -req -in "$SRV_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" \
      -CAserial "$CA_SRL" -CAcreateserial \
      -out "$SRV_CRT" -days 1825 -sha256 \
      -extfile <(printf '%s\n' \
        'basicConstraints=CA:FALSE' \
        'keyUsage=digitalSignature,keyEncipherment' \
        'extendedKeyUsage=serverAuth,1.3.6.1.5.5.8.2.2' \
        "subjectAltName=${san}") \
      || exiterr "Failed to sign the IKEv2 server certificate."
    rm -f "$SRV_CSR"
    printf '%s\n' "$server_addr" > "$ID_FILE"
  fi
  cp -f "$CA_CRT" /etc/ipsec.d/ca.crt
  cp -f "$SRV_CRT" /etc/ipsec.d/server.crt
  chmod 600 "$CA_KEY" "$SRV_KEY"
  chmod 644 "$CA_CRT" "$SRV_CRT" /etc/ipsec.d/ca.crt /etc/ipsec.d/server.crt
fi

# Create strongSwan swanctl configuration
{
  printf '%s\n' 'connections {'
  if [ "$disable_ipsec_l2tp" != yes ]; then
    cat <<EOF
    l2tp-psk {
        version = 1
        local_addrs = %any
        remote_addrs = %any
        proposals = $ike_proposals
        rekey_time = 0s
        encap = yes
        fragmentation = yes
        dpd_delay = 30s
        dpd_timeout = 300s
        unique = never
        send_certreq = no
        local-psk {
            auth = psk
            id = $public_ip
        }
        remote-psk {
            auth = psk
        }
        children {
            l2tp {
                mode = transport
                local_ts = dynamic[udp/1701]
                remote_ts = dynamic[udp]
                esp_proposals = $esp_proposals
                rekey_time = 0s
                dpd_action = none
            }
        }
    }
EOF
  fi
  if [ "$disable_ipsec_xauth" != yes ]; then
    cat <<EOF
    xauth-psk {
        version = 1
        local_addrs = %any
        remote_addrs = %any
        proposals = $ike_proposals
        rekey_time = 0s
        encap = yes
        fragmentation = yes
        dpd_delay = 30s
        dpd_timeout = 300s
        unique = never
        send_certreq = no
        pools = xauth
        local-psk {
            auth = psk
            id = $public_ip
        }
        remote-psk {
            auth = psk
        }
        remote-xauth {
            auth = xauth
        }
        children {
            xauth {
                local_ts = 0.0.0.0/0
                esp_proposals = $esp_proposals
                rekey_time = 0s
                dpd_action = none
            }
        }
    }
EOF
  fi
  if [ "$ikev2_enabled" = yes ]; then
    cat <<EOF
    ikev2-eap {
        version = 2
        local_addrs = %any
        remote_addrs = %any
        proposals = $ikev2_proposals
        rekey_time = 0s
        encap = yes
        fragmentation = yes
        dpd_delay = 30s
        dpd_timeout = 300s
        unique = never
        send_cert = always
        send_certreq = no
        pools = ikev2
        local {
            auth = pubkey
            certs = server.crt
            id = $server_addr
        }
        remote {
            auth = eap-mschapv2
            eap_id = %any
        }
        children {
            ikev2-eap {
                local_ts = $ikev2_ts
                esp_proposals = $ikev2_esp
                rekey_time = 0s
                dpd_action = none
            }
        }
    }
EOF
  fi
  printf '%s\n' '}'
  printf '%s\n' ''
  printf '%s\n' 'pools {'
  if [ "$disable_ipsec_xauth" != yes ]; then
    cat <<EOF
    xauth {
        addrs = $XAUTH_POOL
        dns = $dns_list
    }
EOF
  fi
  if [ "$ikev2_enabled" = yes ]; then
    cat <<EOF
    ikev2 {
        addrs = $ikev2_addrs
        dns = $dns_list
    }
EOF
  fi
  printf '%s\n' '}'
  printf '%s\n' ''
  printf '%s\n' 'secrets {'
  if [ "$disable_ipsec_l2tp" != yes ] || [ "$disable_ipsec_xauth" != yes ]; then
    printf '    ike-psk {\n        secret = "%s"\n    }\n' "$VPN_IPSEC_PSK"
  fi
  if [ "$ikev2_enabled" = yes ]; then
    printf '%s\n' '    private-server {' '        file = server.key' '    }'
  fi
  secret_index=0
  emit_user_secret() {
    secret_index=$((secret_index + 1))
    if [ "$disable_ipsec_xauth" != yes ]; then
      printf '    xauth-%s {\n        id = "%s"\n        secret = "%s"\n    }\n' \
        "$secret_index" "$1" "$2"
    fi
    if [ "$ikev2_enabled" = yes ]; then
      printf '    eap-%s {\n        id = "%s"\n        secret = "%s"\n    }\n' \
        "$secret_index" "$1" "$2"
    fi
  }
  emit_user_secret "$VPN_USER" "$VPN_PASSWORD"
  if [ -n "$VPN_ADDL_USERS" ] && [ -n "$VPN_ADDL_PASSWORDS" ]; then
    count=1
    addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -d ' ' -f 1)
    addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -d ' ' -f 1)
    while [ -n "$addl_user" ] && [ -n "$addl_password" ]; do
      emit_user_secret "$addl_user" "$addl_password"
      count=$((count + 1))
      addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -s -d ' ' -f "$count")
      addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -s -d ' ' -f "$count")
    done
  fi
  printf '%s\n' '}'
} > /etc/swanctl/swanctl.conf
chmod 600 /etc/swanctl/swanctl.conf

if [ "$ikev2_enabled" = yes ]; then
  : > /etc/ipsec.d/eap-users
  printf '%s\n' "$VPN_USER" >> /etc/ipsec.d/eap-users
  safe_user=$(printf '%s' "$VPN_USER" | tr -c 'A-Za-z0-9_.-' '_')
  write_mobileconfig "$VPN_USER" "$VPN_PASSWORD" "/etc/ipsec.d/${safe_user}.mobileconfig" "$include_eap_pass"
  if [ -n "$VPN_ADDL_USERS" ] && [ -n "$VPN_ADDL_PASSWORDS" ]; then
    count=1
    addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -d ' ' -f 1)
    addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -d ' ' -f 1)
    while [ -n "$addl_user" ] && [ -n "$addl_password" ]; do
      printf '%s\n' "$addl_user" >> /etc/ipsec.d/eap-users
      safe_user=$(printf '%s' "$addl_user" | tr -c 'A-Za-z0-9_.-' '_')
      write_mobileconfig "$addl_user" "$addl_password" "/etc/ipsec.d/${safe_user}.mobileconfig" "$include_eap_pass"
      count=$((count + 1))
      addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -s -d ' ' -f "$count")
      addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -s -d ' ' -f "$count")
    done
  fi
  chmod 644 /etc/ipsec.d/eap-users
fi

# Create xl2tpd config
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lns default]
ip range = $L2TP_POOL
local ip = $L2TP_LOCAL
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Set xl2tpd options
cat > /etc/ppp/options.xl2tpd <<EOF
+mschap-v2
ipcp-accept-local
ipcp-accept-remote
noccp
auth
mtu 1280
mru 1280
proxyarp
lcp-echo-failure 4
lcp-echo-interval 30
connect-delay 5000
ms-dns $DNS_SRV1
EOF

if [ -z "$VPN_DNS_SRV1" ] || [ -n "$VPN_DNS_SRV2" ]; then
cat >> /etc/ppp/options.xl2tpd <<EOF
ms-dns $DNS_SRV2
EOF
fi

# Create VPN credentials
cat > /etc/ppp/chap-secrets <<EOF
"$VPN_USER" l2tpd "$VPN_PASSWORD" *
EOF

if [ -n "$VPN_ADDL_USERS" ] && [ -n "$VPN_ADDL_PASSWORDS" ]; then
  count=1
  addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -d ' ' -f 1)
  addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -d ' ' -f 1)
  addl_ip=$(printf '%s' "$VPN_ADDL_IP_ADDRS" | cut -d ' ' -f 1)
  while [ -n "$addl_user" ] && [ -n "$addl_password" ]; do
    addl_ip_l2tp="$addl_ip"
    if [ "$addl_ip" = "*" ] || ! check_ip "$addl_ip"; then
      addl_ip_l2tp=""
    elif [ "$L2TP_NET" = "192.168.42.0/24" ]; then
      addl_ip_part=$(printf '%s' "$addl_ip" | cut -f 1-3 -d '.')
      if [ "$addl_ip_part" != "192.168.42" ]; then
        addl_ip_l2tp=""
      fi
    elif ! ip_in_cidr "$addl_ip" "$L2TP_NET"; then
      addl_ip_l2tp=""
    fi
cat >> /etc/ppp/chap-secrets <<EOF
"$addl_user" l2tpd "$addl_password" ${addl_ip_l2tp:-*}
EOF
    count=$((count+1))
    addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -s -d ' ' -f "$count")
    addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -s -d ' ' -f "$count")
    addl_ip=$(printf '%s' "$VPN_ADDL_IP_ADDRS" | cut -s -d ' ' -f "$count")
  done
fi

# Update sysctl settings
syt='/sbin/sysctl -e -q -w'
$syt kernel.msgmnb=65536 2>/dev/null
$syt kernel.msgmax=65536 2>/dev/null
$syt net.ipv4.ip_forward=1 2>/dev/null
$syt net.ipv4.conf.all.accept_redirects=0 2>/dev/null
$syt net.ipv4.conf.all.send_redirects=0 2>/dev/null
$syt net.ipv4.conf.all.rp_filter=0 2>/dev/null
$syt net.ipv4.conf.default.accept_redirects=0 2>/dev/null
$syt net.ipv4.conf.default.send_redirects=0 2>/dev/null
$syt net.ipv4.conf.default.rp_filter=0 2>/dev/null
$syt "net.ipv4.conf.$NET_IFACE.send_redirects=0" 2>/dev/null
$syt "net.ipv4.conf.$NET_IFACE.rp_filter=0" 2>/dev/null
$syt net.ipv4.tcp_rmem="4096 87380 16777216" 2>/dev/null
$syt net.ipv4.tcp_wmem="4096 87380 16777216" 2>/dev/null
if [ -n "$ip6" ]; then
  $syt net.ipv6.conf.all.forwarding=1 2>/dev/null
fi
if modprobe -q tcp_bbr 2>/dev/null \
  && printf '%s\n%s' "4.20" "$(uname -r)" | sort -C -V; then
  $syt net.ipv4.tcp_congestion_control=bbr 2>/dev/null
fi

# Create IPTables rules
ipi='iptables -I INPUT'
ipf='iptables -I FORWARD'
ipp='iptables -t nat -I POSTROUTING'
res='RELATED,ESTABLISHED'
modprobe -q ip_tables 2>/dev/null
if ! iptables -t nat -C POSTROUTING -s "$L2TP_NET" -o "$NET_IFACE" -j MASQUERADE 2>/dev/null; then
  $ipi 1 -p udp --dport 1701 -m policy --dir in --pol none -j DROP
  $ipi 2 -m conntrack --ctstate INVALID -j DROP
  $ipi 3 -m conntrack --ctstate "$res" -j ACCEPT
  $ipi 4 -p udp -m multiport --dports 500,4500 -j ACCEPT
  $ipi 5 -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
  $ipi 6 -p udp --dport 1701 -j DROP
  $ipf 1 -m conntrack --ctstate INVALID -j DROP
  $ipf 2 -i "$NET_IFACE" -o ppp+ -m conntrack --ctstate "$res" -j ACCEPT
  $ipf 3 -i ppp+ -o "$NET_IFACE" -j ACCEPT
  $ipf 4 -i ppp+ -o ppp+ -j ACCEPT
  $ipf 5 -i "$NET_IFACE" -d "$XAUTH_NET" -m conntrack --ctstate "$res" -j ACCEPT
  $ipf 6 -s "$XAUTH_NET" -o "$NET_IFACE" -j ACCEPT
  $ipf 7 -s "$XAUTH_NET" -o ppp+ -j ACCEPT
  $ipf 8 -i "$NET_IFACE" -d "$IKEV2_NET" -m conntrack --ctstate "$res" -j ACCEPT
  $ipf 9 -s "$IKEV2_NET" -o "$NET_IFACE" -j ACCEPT
  # Client-to-client traffic is allowed by default. To *disallow* such traffic,
  # uncomment below and restart the Docker container.
  # $ipf 2 -i ppp+ -o ppp+ -s "$L2TP_NET" -d "$L2TP_NET" -j DROP
  # $ipf 3 -s "$XAUTH_NET" -d "$XAUTH_NET" -j DROP
  # $ipf 4 -i ppp+ -d "$XAUTH_NET" -j DROP
  # $ipf 5 -s "$XAUTH_NET" -o ppp+ -j DROP
  iptables -A FORWARD -j DROP
  if ! $ipp -s "$XAUTH_NET" -o "$NET_IFACE" -m policy --dir out --pol none -j MASQUERADE; then
    $ipp -s "$XAUTH_NET" -o "$NET_IFACE" ! -d "$XAUTH_NET" -j MASQUERADE
  fi
  $ipp -s "$L2TP_NET" -o "$NET_IFACE" -j MASQUERADE
  $ipp -s "$IKEV2_NET" -o "$NET_IFACE" -j MASQUERADE
fi

if [ -n "$ip6" ]; then
  modprobe -q ip6_tables 2>/dev/null
  if ip6tables -t nat -L >/dev/null 2>&1; then
    ipi6='ip6tables -I INPUT'
    ipf6='ip6tables -I FORWARD'
    ipp6='ip6tables -t nat -I POSTROUTING'
    if ! ip6tables -t nat -C POSTROUTING -s "$IP6_NET" -o "$NET_IFACE" \
        -j MASQUERADE 2>/dev/null; then
      $ipi6 1 -m conntrack --ctstate INVALID -j DROP
      $ipi6 2 -m conntrack --ctstate "$res" -j ACCEPT
      $ipi6 3 -p udp -m multiport --dports 500,4500 -j ACCEPT
      $ipf6 1 -m conntrack --ctstate INVALID -j DROP
      $ipf6 2 -i "$NET_IFACE" -d "$IP6_NET" -m conntrack --ctstate "$res" -j ACCEPT
      $ipf6 3 -s "$IP6_NET" -o "$NET_IFACE" -j ACCEPT
      if ! $ipp6 -s "$IP6_NET" -o "$NET_IFACE" \
          -m policy --dir out --pol none -j MASQUERADE; then
        $ipp6 -s "$IP6_NET" -o "$NET_IFACE" ! -d "$IP6_NET" -j MASQUERADE
      fi
    fi
  fi
fi

case $VPN_ANDROID_MTU_FIX in
  [yY][eE][sS])
    echo
    echo "Applying fix for Android MTU/MSS issues..."
    iptables -t mangle -A FORWARD -m policy --pol ipsec --dir in \
      -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 \
      -j TCPMSS --set-mss 1360
    iptables -t mangle -A FORWARD -m policy --pol ipsec --dir out \
      -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 \
      -j TCPMSS --set-mss 1360
    echo 1 > /proc/sys/net/ipv4/ip_no_pmtu_disc
    ;;
esac

# Update file attributes
chmod 600 /etc/ppp/chap-secrets
if [ -f /etc/swanctl/swanctl.conf ]; then
  chmod 600 /etc/swanctl/swanctl.conf
fi

echo
echo "Starting strongSwan ($os_type/$os_arch)..."
modprobe -q xfrm_user 2>/dev/null || true
modprobe -q esp4 2>/dev/null || true
modprobe -q ah4 2>/dev/null || true
if [ -f /etc/strongswan.d/charon/resolve.conf ]; then
  printf '%s\n' 'resolve {' '    load = no' '}' > /etc/strongswan.d/charon/resolve.conf
fi
for plug in eap-mschapv2 eap-identity xauth-generic; do
  plug_conf="/etc/strongswan.d/charon/${plug}.conf"
  if [ -f "$plug_conf" ]; then
    sed -i 's/load = no/load = yes/' "$plug_conf"
  fi
done
if [ "$sha2_truncbug" = yes ] && [ -f /etc/strongswan.d/charon/kernel-netlink.conf ]; then
  if grep -q 'sha256_96' /etc/strongswan.d/charon/kernel-netlink.conf; then
    sed -i 's/sha256_96 = no/sha256_96 = yes/' /etc/strongswan.d/charon/kernel-netlink.conf
  else
    sed -i '/kernel-netlink {/a\    sha256_96 = yes' /etc/strongswan.d/charon/kernel-netlink.conf
  fi
fi
if [ ! -f /etc/strongswan.conf ] || ! grep -q 'strongswan\.d/\*\.conf' /etc/strongswan.conf; then
  cat > /etc/strongswan.conf <<'EOF'
charon {
    load_modular = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
}
include strongswan.d/*.conf
EOF
fi
cat > /etc/strongswan.d/charon-logging.conf <<'EOF'
charon {
    install_virtual_ip = yes
    install_routes = yes
    make_before_break = yes
    filelog {
        stdout {
            default = 1
            ike = 1
            knl = 1
            cfg = 2
            net = 1
            ike_name = yes
            append = yes
            flush_line = yes
        }
    }
}
EOF

charon_bin=
for c in /usr/lib/strongswan/charon /usr/lib/ipsec/charon /usr/libexec/ipsec/charon /usr/sbin/charon; do
  if [ -x "$c" ]; then
    charon_bin=$c
    break
  fi
done
[ -n "$charon_bin" ] || exiterr "strongSwan charon was not found."
rm -f /var/run/charon.vici /run/charon.vici
nohup "$charon_bin" >/proc/1/fd/1 2>&1 &
charon_pid=$!
echo "$charon_pid" > /var/run/charon.pid
disown "$charon_pid" 2>/dev/null || true
vici_ready=0
for _ in $(seq 1 50); do
  if [ -S /var/run/charon.vici ] || [ -S /run/charon.vici ]; then
    vici_ready=1
    break
  fi
  if ! kill -0 "$charon_pid" 2>/dev/null; then
    exiterr "strongSwan charon exited during startup. The kernel may be missing IPsec (xfrm) support."
  fi
  sleep 0.1
done
[ "$vici_ready" = 1 ] || exiterr "Timed out waiting for the strongSwan vici socket."
swanctl --load-all || exiterr "swanctl --load-all failed."
export charon_bin
(
  while true; do
    sleep 20
    if [ ! -S /var/run/charon.vici ] && [ ! -S /run/charon.vici ]; then
      echo "strongSwan charon is down; restarting..." >&2
      nohup "$charon_bin" >/proc/1/fd/1 2>&1 &
      echo $! > /var/run/charon.pid
      waited=0
      while [ "$waited" -lt 50 ]; do
        if [ -S /var/run/charon.vici ] || [ -S /run/charon.vici ]; then
          swanctl --load-all >&2 || true
          break
        fi
        waited=$((waited + 1))
        sleep 0.1
      done
    fi
  done
) >/proc/1/fd/1 2>&1 &
disown $! 2>/dev/null || true

if [ -n "$VPN_DNS_NAME" ]; then
  server_text="Server"
else
  server_text="Server IP"
fi

if [ "$disable_ipsec_l2tp" != yes ] || [ "$disable_ipsec_xauth" != yes ]; then
cat <<EOF

================================================

IPsec VPN server is now ready for use!

Connect to your new VPN with these details:

$server_text: $server_addr
IPsec PSK: $VPN_IPSEC_PSK
Username: $VPN_USER
Password: $VPN_PASSWORD
EOF
  if [ -n "$VPN_ADDL_USERS" ] && [ -n "$VPN_ADDL_PASSWORDS" ]; then
    count=1
    addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -d ' ' -f 1)
    addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -d ' ' -f 1)
cat <<'EOF'

Additional VPN users (username | password):
EOF
    while [ -n "$addl_user" ] && [ -n "$addl_password" ]; do
cat <<EOF
$addl_user | $addl_password
EOF
      count=$((count+1))
      addl_user=$(printf '%s' "$VPN_ADDL_USERS" | cut -s -d ' ' -f "$count")
      addl_password=$(printf '%s' "$VPN_ADDL_PASSWORDS" | cut -s -d ' ' -f "$count")
    done
  fi
cat <<'EOF'

Write these down. You'll need them to connect!

VPN client setup: https://vpnsetup.net/clients2

================================================
EOF
fi

if [ "$ikev2_enabled" = yes ]; then
  if ! swanctl --list-conns 2>/dev/null | grep -q 'ikev2-eap'; then
    echo "Warning: IKEv2 EAP-MSCHAPv2 connection was not loaded." >&2
  fi
cat <<EOF

================================================

IKEv2 EAP-MSCHAPv2 is ready.

$server_text: $server_addr
Username: $VPN_USER
Password: $VPN_PASSWORD
Client address pool: $IKEV2_POOL
CA certificate: /etc/ipsec.d/ca.crt
Apple profile: /etc/ipsec.d/$(printf '%s' "$VPN_USER" | tr -c 'A-Za-z0-9_.-' '_').mobileconfig

Install the CA on each client, then connect with IKEv2 and
EAP-MSCHAPv2 (username/password). The server address must match
the certificate identity above.

Windows: VPN type IKEv2, authentication "Microsoft: Secured password (EAP-MSCHAP v2)".
Android 11+: IKEv2/IPSec MSCHAPv2.
iOS/macOS: install the .mobileconfig profile, then enable full trust for the CA.

List users: docker exec <container> ikev2.sh --listclients

================================================

EOF
fi

# Start xl2tpd
mkdir -p /var/run/xl2tpd
rm -f /var/run/xl2tpd.pid
exec /usr/sbin/xl2tpd -D -c /etc/xl2tpd/xl2tpd.conf
