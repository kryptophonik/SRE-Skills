#!/usr/bin/env bash
# Lab certificates for docs/examples/07-tls-expiry-audit.md: a private root CA, a short-lived
# intermediate, and six leaf certs with chosen lifetimes. Run in an empty scratch directory.
# Needs OpenSSL 3.4+ (x509 -not_before/-not_after) and GNU date. Keys stay in this directory: delete it after.
set -euo pipefail
k(){ openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1.key" 2>/dev/null; }
k ca; openssl req -x509 -new -key ca.key -subj "/CN=Lab Root CA" -days 3650 -out ca.pem
k inter; openssl req -new -key inter.key -subj "/CN=Lab Issuing CA 2" -out inter.csr
printf 'basicConstraints=critical,CA:TRUE\nkeyUsage=keyCertSign,cRLSign\n' > ca.ext
openssl x509 -req -in inter.csr -CA ca.pem -CAkey ca.key -days 10 -extfile ca.ext -out inter.pem 2>/dev/null
leaf(){ # name days issuer [notbefore notafter]
  k "$1"; openssl req -new -key "$1.key" -subj "/CN=$1.shop.lab" -addext "subjectAltName=DNS:$1.shop.lab,DNS:localhost" -out "$1.csr"
  printf 'subjectAltName=DNS:%s.shop.lab,DNS:localhost\n' "$1" > "$1.ext"
  if [ $# -ge 5 ]; then openssl x509 -req -in "$1.csr" -CA "$3.pem" -CAkey "$3.key" -not_before "$4" -not_after "$5" -extfile "$1.ext" -out "$1.pem" 2>/dev/null
  else openssl x509 -req -in "$1.csr" -CA "$3.pem" -CAkey "$3.key" -days "$2" -extfile "$1.ext" -out "$1.pem" 2>/dev/null; fi; }
leaf api 5 ca; leaf grafana 12 ca; leaf checkout 20 ca; leaf docs 90 ca
leaf legacy 0 ca "$(date -u -d '80 days ago' +%Y%m%d%H%M%SZ)" "$(date -u -d '3 days ago' +%Y%m%d%H%M%SZ)"
leaf vpn 200 inter
cat vpn.pem inter.pem > vpn-chain.pem
rm -f ./*.csr ./*.ext
