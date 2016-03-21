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

