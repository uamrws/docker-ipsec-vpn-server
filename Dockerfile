#
# Copyright (C) 2021-2026 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!
#
# Derivative: Libreswan is replaced by strongSwan, with IKEv2 EAP-MSCHAPv2.

FROM alpine:3.23

WORKDIR /opt/src

RUN set -x \
    && apk add --no-cache \
         bash bind-tools ca-certificates coreutils openssl uuidgen wget xl2tpd \
         iptables iptables-legacy ip6tables iproute2 strongswan \
    && cd /sbin \
    && for fn in iptables iptables-save iptables-restore \
                 ip6tables ip6tables-save ip6tables-restore; do \
         ln -fs xtables-legacy-multi "$fn"; done \
    && find /usr/lib /usr/libexec -name 'libstrongswan-eap-mschapv2.so' | grep -q .

COPY ./ikev2.sh /opt/src/ikev2.sh
COPY ./run.sh /opt/src/run.sh
COPY ./LICENSE.md /opt/src/LICENSE.md
RUN chmod 755 /opt/src/run.sh /opt/src/ikev2.sh \
    && ln -sf /opt/src/ikev2.sh /usr/bin/ikev2.sh
EXPOSE 500/udp 4500/udp
CMD ["/opt/src/run.sh"]

ARG BUILD_DATE
ARG VERSION
ARG VCS_REF
ENV IMAGE_VER=$BUILD_DATE

LABEL maintainer="Lin Song <linsongui@gmail.com>" \
    org.opencontainers.image.created="$BUILD_DATE" \
    org.opencontainers.image.version="$VERSION" \
    org.opencontainers.image.revision="$VCS_REF" \
    org.opencontainers.image.authors="Lin Song <linsongui@gmail.com>" \
    org.opencontainers.image.title="IPsec VPN Server on Docker" \
    org.opencontainers.image.description="Docker image to run an IPsec VPN server with strongSwan (IPsec/L2TP, Cisco IPsec, and IKEv2 EAP-MSCHAPv2)." \
    org.opencontainers.image.url="https://github.com/hwdsl2/docker-ipsec-vpn-server" \
    org.opencontainers.image.source="https://github.com/hwdsl2/docker-ipsec-vpn-server" \
    org.opencontainers.image.documentation="https://github.com/hwdsl2/docker-ipsec-vpn-server"
