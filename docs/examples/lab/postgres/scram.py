#!/usr/bin/env python3
"""Print a PostgreSQL SCRAM-SHA-256 verifier for the password in FILE.

Usage: scram.py FILE. The clear-text password never leaves this process: setup.sh
sends only the verifier to the server, so neither the server log nor
pg_stat_statements sees the password itself.
Format: https://www.postgresql.org/docs/current/catalog-pg-authid.html
"""
import base64, hashlib, hmac, os, sys

def b64(b):
    return base64.b64encode(b).decode()

with open(sys.argv[1], "rb") as f:
    pw = f.read().strip()
salt, iters = os.urandom(16), 4096
salted = hashlib.pbkdf2_hmac("sha256", pw, salt, iters)
client_key = hmac.new(salted, b"Client Key", hashlib.sha256).digest()
stored_key = hashlib.sha256(client_key).digest()
server_key = hmac.new(salted, b"Server Key", hashlib.sha256).digest()
print("SCRAM-SHA-256$%d:%s$%s:%s" % (iters, b64(salt), b64(stored_key), b64(server_key)))
