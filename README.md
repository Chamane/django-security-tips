# Django and PostgreSQL security tips and practices

## Purpose

The aim of this skeleton repo is to learn and promote secure system administration tips and practices in the Django community. Let's keep it concise but include lots of copy-pastable material in order to be usable by beginners as well.

## Database roles, schemas, and migrations

PostgreSQL has something called [schemas](http://www.postgresql.org/docs/current/static/ddl-schemas.html), which are a bit like folders in the file system.
By default, all tables are created in a schema called `public` where all new users/roles have all permissions.
However, it is advisable to confine your web application to a specific schema and grant it as few privileges as possible.

To get started, let's create a database and log into it. If you don't want to type your password every time, create a [password file](http://www.postgresql.org/docs/current/static/libpq-pgpass.html).

```sh
sudo su postgres
createdb playdb && psql playdb
```

We will have no need for the public schema, so let's drop it so that we don't have to think about it anymore.
(Don't do this on an existing database!)

```sql
DROP SCHEMA public CASCADE;
```

We'll have two roles, `djangouser` and `djangomigrator`.
The `djangouser` will run your app in the production, and `djangomigrator` will perform migrations.
The `djangouser` will need permissions to select, insert, delete, and update rows on all the tables.
In addition, she'll need to access the [sequences](http://www.postgresql.org/docs/current/static/functions-sequence.html) to calculate the id of new model instances.
The lesson to learn is that she should have *only* those privileges, and not be able to for example create [trigger procedures](http://www.postgresql.org/docs/current/static/plpgsql-trigger.html).

As the `djangouser` will not be able to create or alter tables, we'll need another role for that purpose, `djangomigrator`, who will be the owner of the schema `playschema` of your django project `playproject`.
In addition, we'll set the [search path](http://www.postgresql.org/docs/current/static/runtime-config-client.html) of both users to `playschema`.

```sql
CREATE ROLE djangomigrator LOGIN ENCRYPTED PASSWORD 'migratorpass';
CREATE ROLE djangouser LOGIN ENCRYPTED PASSWORD 'userpass';
CREATE SCHEMA playschema AUTHORIZATION djangomigrator;
GRANT USAGE ON SCHEMA playschema TO djangouser;
ALTER ROLE djangouser SET SEARCH_PATH TO playschema;
ALTER ROLE djangomigrator SET SEARCH_PATH TO playschema;
```

(or try `psql -d playdb -f roles.sql` in this repo)

In order to juggle between these two roles you can create a special settings file `migrator_settings.py` for your migrator.
It's nothing more than

```python
from .settings import *
DATABASES['default']['USER'] = 'djangomigrator'
DATABASES['default']['PASSWORD'] = 'migratorpass'
```

and then you'll be able to run:

```sh
python manage.py migrate --settings=playproject.migrator_settings
```

By the way, make sure that `python manage.py migrate` really fails!
We are not quite done yet, though, because `djangouser` will, by default, not have any privileges on the newly created tables or sequences.
Before running `python manage.py runserver` you will have to say

```sql
GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES IN SCHEMA playschema TO djangouser;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA playschema TO djangouser;
```

Finally, you probably want the migrations process to be a single simple command. To do that, see for example the file `migrate.sh`.

---
