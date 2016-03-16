CREATE ROLE djangomigrator LOGIN ENCRYPTED PASSWORD 'migratorpass';
CREATE ROLE djangouser LOGIN ENCRYPTED PASSWORD 'userpass';
CREATE SCHEMA playschema AUTHORIZATION djangomigrator;
GRANT USAGE ON SCHEMA playschema TO djangouser;
ALTER ROLE djangouser SET SEARCH_PATH TO playschema;
ALTER ROLE djangomigrator SET SEARCH_PATH TO playschema;
