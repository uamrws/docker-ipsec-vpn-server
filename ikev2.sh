#!/bin/bash
#
# IKEv2 certificate client helper for the strongSwan-based IPsec VPN image.
#
# Derivative of https://github.com/hwdsl2/docker-ipsec-vpn-server
# Copyright (C) 2016-2026 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Manages the original IKEv2 machine-certificate clients (.p12, .sswan, .mobileconfig).
# EAP-MSCHAPv2 users come from VPN_USER / VPN_ADDL_USERS and are not stored here.

set -eu

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

CONF_DIR=/etc/ipsec.d
CONF_FILE=$CONF_DIR/ikev2.conf
ID_FILE=$CONF_DIR/ikev2-server-id
CA_KEY=$CONF_DIR/private/ca.key
CA_CRT=$CONF_DIR/swanctl/x509ca/ca.crt
CA_DB=$CONF_DIR/ca-db
CA_CNF=$CA_DB/openssl.cnf
CRL_FILE=$CONF_DIR/swanctl/x509crl/crl.pem
CLIENT_DIR=$CONF_DIR/clients
EXPORT_DIR=$CONF_DIR/
EAP_USERS=$CONF_DIR/eap-users

exiterr() { echo "Error: $1" >&2; exit 1; }

check_client_name() {
  [ -n "$1" ] && [ "${#1}" -le 64 ] && printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_-]+$'
}

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

use_config_password=0
case ${VPN_PROTECT_CONFIG-} in
  [yY][eE][sS]) use_config_password=1 ;;
esac

client_validity=${VPN_CLIENT_VALIDITY:-120}
if ! printf '%s' "$client_validity" | grep -Eq '^[0-9]+$' \
    || [ "$client_validity" -lt 1 ] || [ "$client_validity" -gt 120 ]; then
  client_validity=120
fi

ensure_ca_db() {
  [ -s "$CA_KEY" ] && [ -s "$CA_CRT" ] || exiterr "IKEv2 CA was not found. Start the container with /etc/ipsec.d mounted."
  mkdir -p "$CA_DB/newcerts" "$CLIENT_DIR" "$(dirname "$CRL_FILE")"
  chmod 700 "$CA_DB" "$CLIENT_DIR"
  if [ ! -f "$CA_DB/index.txt" ]; then
    : > "$CA_DB/index.txt"
  fi
  if [ ! -s "$CA_DB/index.txt.attr" ]; then
    printf '%s\n' 'unique_subject = no' > "$CA_DB/index.txt.attr"
  fi
  if [ ! -s "$CA_DB/serial" ]; then
    printf '%s\n' 1000 > "$CA_DB/serial"
  fi
  if [ ! -s "$CA_DB/crlnumber" ]; then
    printf '%s\n' 1000 > "$CA_DB/crlnumber"
  fi
  cat > "$CA_CNF" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir = $CA_DB
database = \$dir/index.txt
new_certs_dir = \$dir/newcerts
certificate = $CA_CRT
private_key = $CA_KEY
serial = \$dir/serial
crlnumber = \$dir/crlnumber
default_md = sha256
default_days = 3650
default_crl_days = 3650
policy = policy_anything
unique_subject = no
copy_extensions = none
email_in_dn = no
utf8 = yes

[ policy_anything ]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional
EOF
  chmod 600 "$CA_CNF"
}

load_server_addr() {
  server_addr=$(cat "$ID_FILE" 2>/dev/null || true)
  [ -n "$server_addr" ] || exiterr "Could not get VPN server address."
}

server_from_conf() {
  sed -n "s/^IKEV2_SERVER='\\(.*\\)'/\\1/p" "$CONF_FILE" 2>/dev/null | tail -n 1
}

primary_client_name() {
  local name
  name=$(sed -n "s/^IKEV2_CLIENT='\\(.*\\)'/\\1/p" "$CONF_FILE" 2>/dev/null | tail -n 1)
  if check_client_name "$name"; then
    printf '%s\n' "$name"
  else
    printf '%s\n' "${VPN_CLIENT_NAME:-vpnclient}"
  fi
}

random_token() {
  LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' </dev/urandom | head -c 18 || true
}

get_p12_password() {
  if [ "$use_config_password" = 0 ]; then
    p12_password=$(random_token)
  else
    p12_password=$(sed -n "s/^IKEV2_CONFIG_PASSWORD='\\(.*\\)'/\\1/p" "$CONF_FILE" 2>/dev/null | tail -n 1)
    if [ -z "$p12_password" ] && [ -s "$CONF_DIR/.config-password" ]; then
      p12_password=$(cat "$CONF_DIR/.config-password")
      remember_config_password=1
    fi
    if [ -z "$p12_password" ]; then
      p12_password=$(random_token)
      remember_config_password=1
      printf '%s\n' "$p12_password" > "$CONF_DIR/.config-password"
      chmod 600 "$CONF_DIR/.config-password"
    fi
  fi
  [ -n "$p12_password" ] || exiterr "Could not generate a random password for .p12 file."
}

save_config_password() {
  [ "${remember_config_password:-0}" = 1 ] || return 0
  [ "$use_config_password" = 1 ] || return 0
  if [ -f "$CONF_FILE" ] && grep -q '^IKEV2_CONFIG_PASSWORD=' "$CONF_FILE"; then
    return 0
  fi
  mkdir -p "$CONF_DIR"
  printf '%s\n' "IKEV2_CONFIG_PASSWORD='$p12_password'" >> "$CONF_FILE"
  chmod 600 "$CONF_FILE"
  remember_config_password=0
}

write_conf() {
  local primary=$1
  {
    printf '%s\n' "IKEV2_SERVER='$server_addr'"
    printf '%s\n' "IKEV2_CLIENT='$primary'"
    if [ "$use_config_password" = 1 ] && [ -n "${p12_password:-}" ]; then
      printf '%s\n' "IKEV2_CONFIG_PASSWORD='$p12_password'"
    fi
  } > "$CONF_FILE"
  chmod 600 "$CONF_FILE"
  remember_config_password=0
}

create_client_cert() {
  local key crt csr ext days err
  key=$CLIENT_DIR/$client_name.key
  crt=$CLIENT_DIR/$client_name.crt
  csr=$CLIENT_DIR/$client_name.csr
  ext=$CA_DB/client-ext.cnf
  days=$((client_validity * 365 / 12))
  [ "$days" -ge 1 ] || days=3650
  if [ -s "$crt" ]; then
    exiterr "Client '$client_name' already exists."
  fi
  openssl req -newkey rsa:3072 -nodes -keyout "$key" -out "$csr" \
    -subj "/O=IKEv2 VPN/CN=${client_name}" >/dev/null 2>&1 \
    || exiterr "Failed to generate the client key."
  cat > "$ext" <<EOF
[ v3_client ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = DNS:${client_name}
EOF
  err=$(mktemp)
  if ! openssl ca -config "$CA_CNF" -batch -notext \
      -in "$csr" -out "$crt" \
      -extfile "$ext" -extensions v3_client -days "$days" >/dev/null 2>"$err"; then
    echo "Error: Failed to create client certificate." >&2
    grep -viE 'PRIVATE KEY|-----' "$err" | head -n 20 >&2 || true
    rm -f "$err" "$key" "$crt" "$csr"
    exit 1
  fi
  rm -f "$err" "$csr" "$ext"
  chmod 600 "$key"
  chmod 644 "$crt"
}

pkcs12_export() {
  local pem=$1 outfile=$2 pass=$3
  if openssl pkcs12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -export \
      -legacy -name "$client_name" -in "$pem" -out "$outfile" \
      -passout "pass:${pass}" >/dev/null 2>&1; then
    return 0
  fi
  openssl pkcs12 -export -name "$client_name" -in "$pem" -out "$outfile" \
    -passout "pass:${pass}" >/dev/null 2>&1
}

export_p12_file() {
  local key crt pem enc
  key=$CLIENT_DIR/$client_name.key
  crt=$CLIENT_DIR/$client_name.crt
  [ -s "$key" ] && [ -s "$crt" ] || exiterr "Client '$client_name' was not found."
  get_p12_password
  pem=$(mktemp)
  enc=${EXPORT_DIR}${client_name}.enc.p12
  cat "$key" "$crt" "$CA_CRT" > "$pem"
  pkcs12_export "$pem" "$enc" "$p12_password" || exiterr "Failed to export the client PKCS#12 file."
  if [ "$use_config_password" = 0 ]; then
    pkcs12_export "$pem" "${EXPORT_DIR}${client_name}.p12" "" \
      || exiterr "Failed to export the client PKCS#12 file."
  else
    cp -f "$enc" "${EXPORT_DIR}${client_name}.p12"
  fi
  rm -f "$pem"
  chmod 600 "${EXPORT_DIR}${client_name}.p12"
  save_config_password
}

create_mobileconfig() {
  local enc p12_base64 ca_base64 mc_file uuid_p12 name_xml addr_xml pass_xml
  enc=${EXPORT_DIR}${client_name}.enc.p12
  [ -s "$enc" ] || exiterr "Could not encode .p12 file."
  p12_base64=$(base64 -w 52 "$enc")
  rm -f "$enc"
  [ -n "$p12_base64" ] || exiterr "Could not encode .p12 file."
  ca_base64=$(openssl x509 -in "$CA_CRT" | grep -v CERTIFICATE)
  [ -n "$ca_base64" ] || exiterr "Could not encode CA certificate."
  uuid_p12=$(new_uuid)
  name_xml=$(xml_escape "$client_name")
  addr_xml=$(xml_escape "$server_addr")
  pass_xml=$(xml_escape "$p12_password")
  mc_file=${EXPORT_DIR}${client_name}.mobileconfig
  cat > "$mc_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>IKEv2</key>
      <dict>
        <key>AuthenticationMethod</key>
        <string>Certificate</string>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>19</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256-GCM</string>
          <key>LifeTimeInMinutes</key>
          <integer>1410</integer>
        </dict>
        <key>DeadPeerDetectionRate</key>
        <string>Medium</string>
        <key>DisableRedirect</key>
        <true/>
        <key>EnableCertificateRevocationCheck</key>
        <integer>0</integer>
        <key>EnablePFS</key>
        <integer>0</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>19</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256-GCM</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA2-256</string>
          <key>LifeTimeInMinutes</key>
          <integer>1410</integer>
        </dict>
        <key>LocalIdentifier</key>
        <string>$name_xml</string>
        <key>PayloadCertificateUUID</key>
        <string>$uuid_p12</string>
        <key>OnDemandEnabled</key>
        <integer>0</integer>
        <key>OnDemandRules</key>
        <array>
          <dict>
            <key>InterfaceTypeMatch</key>
            <string>WiFi</string>
            <key>URLStringProbe</key>
            <string>http://captive.apple.com/hotspot-detect.html</string>
            <key>Action</key>
            <string>Connect</string>
          </dict>
          <dict>
            <key>InterfaceTypeMatch</key>
            <string>Cellular</string>
            <key>Action</key>
            <string>Disconnect</string>
          </dict>
          <dict>
            <key>Action</key>
            <string>Ignore</string>
          </dict>
        </array>
        <key>RemoteAddress</key>
        <string>$addr_xml</string>
        <key>RemoteIdentifier</key>
        <string>$addr_xml</string>
        <key>UseConfigurationAttributeInternalIPSubnet</key>
        <integer>0</integer>
      </dict>
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key>
        <integer>1</integer>
      </dict>
      <key>PayloadDescription</key>
      <string>Configures VPN settings</string>
      <key>PayloadDisplayName</key>
      <string>VPN</string>
      <key>PayloadOrganization</key>
      <string>IKEv2 VPN</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.vpn.managed.$(new_uuid)</string>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key>
      <string>$(new_uuid)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>Proxies</key>
      <dict>
        <key>HTTPEnable</key>
        <integer>0</integer>
        <key>HTTPSEnable</key>
        <integer>0</integer>
      </dict>
      <key>UserDefinedName</key>
      <string>$addr_xml</string>
      <key>VPNType</key>
      <string>IKEv2</string>
    </dict>
    <dict>
EOF
  if [ "$use_config_password" = 0 ]; then
    cat >> "$mc_file" <<EOF
      <key>Password</key>
      <string>$pass_xml</string>
EOF
  fi
  cat >> "$mc_file" <<EOF
      <key>PayloadCertificateFileName</key>
      <string>$name_xml</string>
      <key>PayloadContent</key>
      <data>
$p12_base64
      </data>
      <key>PayloadDescription</key>
      <string>Adds a PKCS#12-formatted certificate</string>
      <key>PayloadDisplayName</key>
      <string>$name_xml</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs12.$(new_uuid)</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>$uuid_p12</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>PayloadContent</key>
      <data>
$ca_base64
      </data>
      <key>PayloadCertificateFileName</key>
      <string>ikev2vpnca</string>
      <key>PayloadDescription</key>
      <string>Adds a CA root certificate</string>
      <key>PayloadDisplayName</key>
      <string>Certificate Authority (CA)</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.root.$(new_uuid)</string>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadUUID</key>
      <string>$(new_uuid)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>IKEv2 VPN $addr_xml</string>
  <key>PayloadIdentifier</key>
  <string>com.apple.vpn.managed.$(new_uuid)</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$(new_uuid)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF
  chmod 600 "$mc_file"
}

create_android_profile() {
  local p12_base64_oneline uuid2 sswan_file addr_json
  p12_base64_oneline=$(base64 -w 52 "${EXPORT_DIR}${client_name}.p12" | sed 's/$/\\n/' | tr -d '\n')
  [ -n "$p12_base64_oneline" ] || exiterr "Could not encode .p12 file."
  uuid2=$(new_uuid)
  addr_json=$(printf '%s' "$server_addr" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  sswan_file=${EXPORT_DIR}${client_name}.sswan
  cat > "$sswan_file" <<EOF
{
  "uuid": "$uuid2",
  "name": "IKEv2 VPN $addr_json",
  "type": "ikev2-cert",
  "remote": {
    "addr": "$addr_json"
  },
  "local": {
    "p12": "$p12_base64_oneline",
    "rsa-pss": "true"
  },
  "ike-proposal": "aes256-sha256-modp2048",
  "esp-proposal": "aes128gcm16"
}
EOF
  chmod 600 "$sswan_file"
}

export_client_config() {
  export_p12_file
  create_mobileconfig
  create_android_profile
}

print_server_info() {
  cat <<EOF
VPN server address: $server_addr

EOF
}

print_client_info() {
  cat <<'EOF'
Client configuration is available inside the
Docker container at:
EOF
  cat <<EOF
${EXPORT_DIR}${client_name}.p12 (for Windows & Linux)
${EXPORT_DIR}${client_name}.sswan (for Android)
${EXPORT_DIR}${client_name}.mobileconfig (for iOS & macOS)
EOF
  if [ "$use_config_password" = 1 ]; then
    cat <<EOF

*IMPORTANT* Password for client config files:
$p12_password
Write this down, you'll need it for import!
EOF
  fi
  cat <<'EOF'

Next steps: Configure IKEv2 clients. See:
https://vpnsetup.net/clients2

================================================
EOF
}

print_setup_complete() {
  cat <<EOF
================================================

IKEv2 setup successful. Details for IKEv2 mode:

VPN server address: $server_addr
VPN client name: $client_name

EOF
  print_client_info
}

print_client_added() {
  cat <<EOF


================================================

New IKEv2 client "$client_name" added!

EOF
  print_server_info
  print_client_info
}

print_client_exported() {
  cat <<EOF


================================================

IKEv2 client "$client_name" exported!

EOF
  print_server_info
  print_client_info
}

cert_state() {
  local name=$1 crt state
  crt=$CLIENT_DIR/$name.crt
  [ -s "$crt" ] || { printf '%s\n' missing; return; }
  state=$(awk -F '\t' -v cn="$name" '
    $6 ~ ("/CN=" cn "$") { state = $1 }
    END { print state }
  ' "$CA_DB/index.txt" 2>/dev/null || true)
  if [ "$state" = "R" ]; then
    printf '%s\n' revoked
    return
  fi
  if ! openssl x509 -in "$crt" -noout -checkend 0 >/dev/null 2>&1; then
    printf '%s\n' expired
    return
  fi
  printf '%s\n' valid
}

list_existing_clients() {
  local name max_len count=0 state
  echo "Checking for existing IKEv2 client(s)..."
  echo
  max_len=16
  for name in "$CLIENT_DIR"/*.crt; do
    [ -e "$name" ] || continue
    name=$(basename "$name" .crt)
    [ "${#name}" -gt "$max_len" ] && [ "${#name}" -le 64 ] && max_len=${#name}
  done
  printf "%-${max_len}s  %s\n" 'Client Name' 'Certificate Status'
  printf "%-${max_len}s  %s\n" '------------' '-------------------'
  for name in "$CLIENT_DIR"/*.crt; do
    [ -e "$name" ] || continue
    name=$(basename "$name" .crt)
    state=$(cert_state "$name")
    printf "%-${max_len}s  %s\n" "$name" "$state"
    count=$((count + 1))
  done
  echo
  if [ "$count" = 1 ]; then
    echo "Total: 1 client"
  else
    echo "Total: $count clients"
  fi
  if [ -s "$EAP_USERS" ]; then
    echo
    echo "EAP-MSCHAPv2 users:"
    cat "$EAP_USERS"
  fi
}

reload_crls() {
  if [ -S /var/run/charon.vici ] || [ -S /run/charon.vici ]; then
    swanctl --load-creds >/dev/null 2>&1 || true
  fi
}

revoke_cert() {
  local crt=$CLIENT_DIR/$client_name.crt
  [ -s "$crt" ] || exiterr "Client '$client_name' was not found."
  openssl ca -config "$CA_CNF" -revoke "$crt" >/dev/null 2>&1 || true
  openssl ca -config "$CA_CNF" -gencrl -out "$CRL_FILE" >/dev/null 2>&1 \
    || exiterr "Failed to update the certificate revocation list."
  chmod 644 "$CRL_FILE"
  reload_crls
}

remove_client_config() {
  local f
  for f in \
      "${EXPORT_DIR}${client_name}.p12" \
      "${EXPORT_DIR}${client_name}.mobileconfig" \
      "${EXPORT_DIR}${client_name}.sswan" \
      "${EXPORT_DIR}${client_name}.enc.p12"; do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      rm -f "$f"
    fi
  done
}

require_client_arg() {
  client_name=${1-}
  check_client_name "$client_name" || exiterr "Invalid client name. Use 1-64 letters, digits, '-' or '_'."
}

usage() {
  cat <<'EOF'
IKEv2 certificate clients (strongSwan)

Commands:
  ikev2.sh --auto                 Create the default client when IKEv2 is not set up
  ikev2.sh --addclient <name>     Add a certificate client and export its config
  ikev2.sh --exportclient <name>  Export .p12, .sswan and .mobileconfig again
  ikev2.sh --listclients          List certificate clients and EAP usernames
  ikev2.sh --revokeclient <name>  Revoke a client certificate
  ikev2.sh --deleteclient <name>  Revoke and delete a client certificate
  ikev2.sh --removeikev2          Remove certificate clients (EAP-MSCHAPv2 is kept)
  ikev2.sh --status               Show the IKEv2 server identity
  ikev2.sh -h                     Show this help

The default client name is vpnclient, or VPN_CLIENT_NAME.
Client files are written to /etc/ipsec.d:
  <name>.p12           client certificate, key and CA (Windows & Linux)
  <name>.sswan         strongSwan Android profile, type ikev2-cert
  <name>.mobileconfig  Apple profile, certificate authentication

The .p12 password is empty unless VPN_PROTECT_CONFIG=yes.
EAP-MSCHAPv2 profiles are separate files named eap-<username>.p12,
eap-<username>.sswan and eap-<username>.mobileconfig.
The EAP .p12 contains the CA certificate, not a client certificate.
EOF
}

cmd=${1-}
case "$cmd" in
  -h|--help|"")
    usage
    ;;
  --auto)
    load_server_addr
    ensure_ca_db
    client_name=${VPN_CLIENT_NAME:-vpnclient}
    check_client_name "$client_name" || exiterr "Invalid VPN_CLIENT_NAME."
    if [ -f "$CONF_FILE" ]; then
      if [ "$(server_from_conf)" = "$server_addr" ]; then
        exit 0
      fi
      updated=0
      for key in "$CLIENT_DIR"/*.key; do
        [ -e "$key" ] || continue
        client_name=$(basename "$key" .key)
        [ -s "$CLIENT_DIR/$client_name.crt" ] || continue
        export_client_config
        updated=1
      done
      [ "$updated" = 1 ] || exit 0
      client_name=$(primary_client_name)
      if [ -f "$CONF_FILE" ]; then
        sed -i "s/^IKEV2_SERVER='.*'/IKEV2_SERVER='$server_addr'/" "$CONF_FILE"
      fi
      print_setup_complete
      exit 0
    fi
    create_client_cert
    export_client_config
    write_conf "$client_name"
    print_setup_complete
    ;;
  --addclient)
    require_client_arg "${2-}"
    load_server_addr
    ensure_ca_db
    create_client_cert
    export_client_config
    if [ ! -f "$CONF_FILE" ]; then
      write_conf "$client_name"
    fi
    print_client_added
    ;;
  --exportclient)
    require_client_arg "${2-}"
    load_server_addr
    ensure_ca_db
    export_client_config
    print_client_exported
    ;;
  --listclients)
    ensure_ca_db
    list_existing_clients
    echo
    ;;
  --revokeclient)
    require_client_arg "${2-}"
    load_server_addr
    ensure_ca_db
    revoke_cert
    rm -f "$CLIENT_DIR/$client_name.key"
    remove_client_config
    echo
    echo "Client '$client_name' revoked!"
    ;;
  --deleteclient)
    require_client_arg "${2-}"
    load_server_addr
    ensure_ca_db
    revoke_cert
    rm -f "$CLIENT_DIR/$client_name.key" "$CLIENT_DIR/$client_name.crt"
    remove_client_config
    echo
    echo "Client '$client_name' deleted!"
    ;;
  --removeikev2)
    if [ -s "$CA_KEY" ] && [ -s "$CA_CRT" ]; then
      ensure_ca_db
      for crt in "$CLIENT_DIR"/*.crt; do
        [ -e "$crt" ] || continue
        client_name=$(basename "$crt" .crt)
        openssl ca -config "$CA_CNF" -revoke "$crt" >/dev/null 2>&1 || true
        rm -f "$CLIENT_DIR/$client_name.key"
        remove_client_config
        rm -f "$crt"
      done
      if ls "$CLIENT_DIR"/*.crt >/dev/null 2>&1 || [ -s "$CA_DB/index.txt" ]; then
        openssl ca -config "$CA_CNF" -gencrl -out "$CRL_FILE" >/dev/null 2>&1 || true
        chmod 644 "$CRL_FILE" 2>/dev/null || true
        reload_crls
      fi
    fi
    rm -f "$CONF_FILE" "$CONF_DIR/ikev2setup.log"
    echo
    echo "IKEv2 removed!"
    ;;
  --status)
    if [ -s "$ID_FILE" ]; then
      echo "IKEv2 server identity: $(cat "$ID_FILE")"
    else
      echo "IKEv2 is not set up. Mount a volume at /etc/ipsec.d and recreate the container."
      exit 1
    fi
    if [ -f "$CONF_FILE" ]; then
      echo "IKEv2 certificate client: $(primary_client_name)"
    else
      echo "IKEv2 certificate mode is not set up."
    fi
    if [ -s "$EAP_USERS" ]; then
      echo "EAP-MSCHAPv2 users:"
      cat "$EAP_USERS"
    fi
    echo "CA certificate: /etc/ipsec.d/ca.crt"
    echo "Server certificate: /etc/ipsec.d/server.crt"
    if command -v swanctl >/dev/null 2>&1 && { [ -S /var/run/charon.vici ] || [ -S /run/charon.vici ]; }; then
      echo
      swanctl --list-conns || true
    fi
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
