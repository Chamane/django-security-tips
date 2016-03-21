# FOR DEBUGGING PURPOSES ONLY FOR GODS SAKE
# run as postgres superuser
dropdb playdb
dropuser djangouser
dropuser djangomigrator
createdb playdb
psql -d playdb -c 'DROP SCHEMA public CASCADE;'
psql -d playdb -f roles.sql
psql -d playdb -f create_auth_schema.sql

# then as a normal unix user. Mind the order of apps.
python manage.py migrate plaything --settings=playproject.migrator_settings
sh migrate.sh
