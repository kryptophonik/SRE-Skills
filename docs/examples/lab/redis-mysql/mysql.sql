-- Run as root by setup.sh, after it creates the users app, sre_ro and operator with generated passwords.
-- Grants for sre_ro follow .claude/skills/sre-database-triage/references/mysql.md ("Access", MySQL 8.4).
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'sre_ro'@'%';
GRANT SELECT ON performance_schema.* TO 'sre_ro'@'%';
GRANT SELECT, EXECUTE ON sys.* TO 'sre_ro'@'%';

-- Operator account for an approved KILL of another user's thread: CONNECTION_ADMIN only.
GRANT CONNECTION_ADMIN ON *.* TO 'operator'@'%';

-- The application.
CREATE DATABASE shop;
GRANT ALL ON shop.* TO 'app'@'%';
CREATE TABLE shop.orders (id INT PRIMARY KEY, status VARCHAR(20) NOT NULL);
INSERT INTO shop.orders VALUES (1, 'paid'), (2, 'paid');
