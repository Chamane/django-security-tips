# Django and PostgreSQL security tips and practices

## Contents

* [Database roles, schemas, and migrations](#database-roles-schemas-and-migrations)
* [User passwords](#user-passwords)
* [Firewall](#database-cluster-firewall)
* [Database separation](#database-separation)
* [Further reading](#further-reading)

## Purpose and motivation ##

The aim of this guide/repository is to learn and promote secure system administration tips and practices in the Django community.
My motivation is that most articles that focus on getting a Django application up and running do not talk much about security, yet database security guides often feel too abstract and intimidating for newcomers.
So let's bridge that gap!
By pinning down PostgreSQL as the database I do not mean to discourage the use any other system -- it's just that I want to provide concrete code help readers get their hands dirty, so a choice has to be made.

The scope of the guide is yet to be defined and will depend on the people who will get involved.
Your questions, feedback, and insight well be very welcome!

## Before we begin..

.. Make sure you have read the
[Django Deployment Checklist](https://docs.djangoproject.com/en/dev/howto/deployment/checklist/)
and
[Security in Django](https://docs.djangoproject.com/en/dev/topics/security/).

This skeleton has been created by commands
```sh
django-admin startproject playproject
django-admin startapp plaything
```

## Database roles, schemas, and migrations

PostgreSQL has something called [schemas](http://www.postgresql.org/docs/current/static/ddl-schemas.html), which are a bit like folders in the file system.
By default, all tables are created in a schema called `public` where all new users/roles have rather wide permissions.
However, it is advisable to confine your web application to a specific schema and grant it as few privileges as possible.

To get started, let's create a database and log into it.

```sh
sudo su postgres
createdb playdb && psql playdb
```

We will have no need for the public schema, so let's drop it.
(Make sure it's not used by anyone!)

```sql
DROP SCHEMA public CASCADE;
```

We'll have two roles, `djangouser` and `djangomigrator`.
The `djangouser` will be used by your application in production, and `djangomigrator` will be used to perform migrations.
The `djangouser` will need permissions to select, insert, delete, and update rows on all the tables.
In addition, she'll need to access the [sequences](http://www.postgresql.org/docs/current/static/functions-sequence.html) to calculate the id of new model instances.
The lesson to learn is that she should have *only* those privileges.

**Why bother with two roles?**
* When every user's permissions are as narrow as possible, you will have an easier time debugging the system when you suspect a security breach.
* Not everybody is interested in your data. If `djangouser` can create tables, a successful attacker can use your database for their own purposes.
* If an attacker can create [trigger procedures](http://www.postgresql.org/docs/current/static/plpgsql-trigger.html), those procedures will persist even after password rotation and you might not notice for a long time. Considerable harm and snooping will ensue.

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

## User passwords

The default password management in Django depends on your database user, i.e. `djangouser` in our case, to have `SELECT` privileges in the table `auth_user`.
Go ahead, try that by running

```sql
SELECT * FROM auth_user;
```

in your dbshell.
That's pretty scary in case you fall victim to an SQL injection attack.

The easiest way to mitigate that threat is to use state of the art hash functions, as explained in the [Django documentation](http://django.readthedocs.org/en/latest/topics/auth/passwords.html).
However, allowing `SELECT` on your password hashes is fundamentally insecure and you might want to consider an external identity management solution.

Alternatively, there is an approach I learnt from [tsavola](https://github.com/tsavola).
PostgreSQL has something called SECURITY DEFINER functions which can perform certain activities with special privileges, a bit like `sudo` on Unix systems.
This makes it possible to revoke the `SELECT` privileges on your password hashes but still be able to compare them as a regular user.
More precisely:

* Make an SQL function called `check_password()` that will take in a user ID and a hash, and will return true if the user's hash in the database matches the one in the arguments.
* That function is defined by the database superuser and flagged as `SECURITY DEFINER`, so that inside the function it can `SELECT` the existing hashes.
* Then `django.contrib.auth.models.User.check_password()` will, instead of taking the hash out of the database, simply call that function.
* While not necessary, to improve readability, I have revoked all permissions from the password hashes and salts from `djangouser` and instead call SQL functions `get_salt()` and `insert_or_update_password()`.

To continue on our previous example, you'll perform the following actions in the database:
```sql
CREATE SCHEMA auth_schema;
GRANT USAGE ON SCHEMA auth_schema TO djangouser;

CREATE TABLE auth_schema.passwords(
    uid bigint PRIMARY KEY,
    pw_salt bytea,
    pw_hash bytea
);

CREATE FUNCTION auth_schema.check_password(IN bigint, IN bytea, OUT bool) AS
$$
    SELECT exists(SELECT 1 FROM auth_schema.passwords WHERE uid = $1 AND pw_hash = $2);
$$
LANGUAGE SQL IMMUTABLE STRICT SECURITY DEFINER;

CREATE FUNCTION auth_schema.get_salt(IN bigint, OUT bytea) AS
$$
    SELECT pw_salt FROM auth_schema.passwords WHERE uid = $1;
$$
LANGUAGE SQL IMMUTABLE STRICT SECURITY DEFINER;

CREATE FUNCTION auth_schema.insert_or_update_password(IN bigint, IN bytea, IN bytea) RETURNS VOID AS
$$
    INSERT INTO auth_schema.passwords (uid, pw_salt, pw_hash) VALUES ($1, $2, $3) ON CONFLICT (uid) DO UPDATE SET pw_hash = EXCLUDED.pw_hash, pw_salt = EXCLUDED.pw_salt;
$$
LANGUAGE SQL VOLATILE STRICT SECURITY DEFINER;

-- REVOKE ALL ON auth_schema.passwords FROM PUBLIC; -- I normally delete the public schema.
ALTER TABLE auth_schema.passwords OWNER TO postgres;
REVOKE ALL ON auth_schema.passwords FROM djangouser;

ALTER FUNCTION auth_schema.check_password(IN bigint, IN bytea, OUT bool) OWNER TO postgres;
ALTER FUNCTION auth_schema.insert_or_update_password(IN bigint, IN bytea, IN bytea) OWNER TO postgres;
ALTER FUNCTION auth_schema.get_salt(IN bigint) OWNER TO postgres;

```

In addition, you'll need to extend the User model ([read the docs](https://docs.djangoproject.com/en/dev/topics/auth/customizing/#extending-user)).


```python
from django.db import models
from django.db import connection
from django.contrib.auth.models import AbstractUser
from django.contrib.auth.hashers import make_password
from django.utils.crypto import get_random_string

class CustomUser(AbstractUser):
    def make_random_password(self):
        length = 35
        allowed_chars='abcdefghjkmnpqrstuvwxyz' + 'ABCDEFGHJKLMNPQRSTUVWXYZ' + '23456789'
        return get_random_string(length, allowed_chars)

    def save(self, *args, **kwargs):
        update_pw = ('update_fields' not in kwargs or 'password' in kwargs['update_fields']) and '$' in self.password
        if update_pw:
            algo, iterations, salt, pw_hash = self.password.split('$', 3)
            # self.password should be unique anyway for get_session_auth_hash()
            self.password = self.make_random_password()

        super(CustomUser, self).save(*args, **kwargs)
        if update_pw:
            cursor = connection.cursor()
            cursor.execute("SELECT auth_schema.insert_or_update_password(%d, '%s', '%s');" % (self.id, salt, pw_hash))
        return

    def check_password(self, raw_password):
        cursor = connection.cursor()
        cursor.execute("SELECT auth_schema.get_salt(%d);" % self.id)
        salt = cursor.fetchone()[0]

        algo, iterations, salt, pw_hash = make_password(raw_password, salt=salt).split('$', 3)
        cursor.execute("SELECT auth_schema.check_password(%d, '%s');" % (self.id, pw_hash))
        pw_correct = cursor.fetchone()[0]
        return bool(pw_correct)
```


And put

```python
AUTH_USER_MODEL = 'plaything.CustomUser'
```

in your settings.py.
Also, to add users in the admin, you'll need to subclass the default forms, [see the docs](https://docs.djangoproject.com/en/1.9/topics/auth/customizing/#custom-users-and-the-built-in-auth-forms).

As a result, only the superuser of your database will ever be able to see the password hashes once they have been saved.

**WARNING:** this solution depends on the function `make_password()` to stay constant.
Future version of Django may for example increase the number of iterations it performs and thus cause the hash comparison to fail.
Make sure you have a plan for that.


## Database cluster firewall

Your database should be accessible only from certain IP address(es).
Even if you are not afraid of attackers, be afraid of yourself accidentally running `dropdb playdb` instead of `dropdb playdb_test`.

For example, on AWS, if you have a Virtual Private Cloud with CIDR 172.38.0.0/16 you can allow inbound TCP traffic on port 5432 from source 172.38.0.0/16.
That will allow connections from any machine in that VPC, so you may want to be even more restrictive.

## Database separation

Privileges can be defined on a number of levels in PostgreSQL: e.g. row, table, schema, and database level.
All of them have their uses, but let's highlight the difference between database and other levels.

* An attacker can change the row, table, or schema with SQL commands,
* but to access a different database, a new connection has to be initiated.

So if something must be kept out of the reach of your web app but still in the same cluster, consider putting it in a different database.

## Read-only replicas

Very useful for security as well as performance. TODO.

## Further reading

* [IBM develperWorks: Total security in a PostgreSQL database](http://www.ibm.com/developerworks/library/os-postgresecurity/)
* [OpenSCG: Security Hardening PostgreSQL](http://www.openscg.com/wp-content/uploads/2013/04/SecurityHardeningPostgreSQL.pdf)
* [OWASP: Backend Security Project PostgreSQL Hardening](https://www.owasp.org/index.php/OWASP_Backend_Security_Project_PostgreSQL_Hardening)

---
