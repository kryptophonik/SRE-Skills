-- Run as postgres by setup.sh (psql runs each statement on its own, so CREATE DATABASE works).
-- Roles follow .claude/skills/sre-database-triage/references/postgres.md ("Access").
-- Passwords are set separately by setup.sh from generated files (SCRAM verifiers, no clear text).

-- Triage role: read-only, capped, guards on the role.
CREATE ROLE sre_ro LOGIN CONNECTION LIMIT 3;
GRANT pg_monitor TO sre_ro;
ALTER ROLE sre_ro SET default_transaction_read_only = on;
ALTER ROLE sre_ro SET statement_timeout = '5s';
ALTER ROLE sre_ro SET lock_timeout = '1s';
ALTER ROLE sre_ro SET idle_in_transaction_session_timeout = '10s';

-- Operator role: used by a human after approval, never by the wrapper.
CREATE ROLE ops LOGIN;
GRANT pg_signal_backend, pg_read_all_stats TO ops;

-- PG16+: both roles may use the reserved_connections slots (setup.sh sets reserved_connections = 3).
GRANT pg_use_reserved_connections TO sre_ro, ops;

-- Application owner.
CREATE ROLE shop LOGIN;
CREATE DATABASE shop OWNER shop;
