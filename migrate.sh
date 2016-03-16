#!/bin/sh
python manage.py migrate --settings=playproject.migrator_settings
psql -h localhost -U djangomigrator -d playdb -c 'GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES IN SCHEMA playschema TO djangouser;'
psql -h localhost -U djangomigrator -d playdb -c 'GRANT USAGE ON ALL SEQUENCES IN SCHEMA playschema TO djangouser;'
