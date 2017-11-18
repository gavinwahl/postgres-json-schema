# postgres-json-schema

[![Build Status](https://travis-ci.org/gavinwahl/postgres-json-schema.svg?branch=master)](https://travis-ci.org/gavinwahl/postgres-json-schema)

postgres-json-schema allows validation of [JSON
schemas](http://json-schema.org/) in PostgreSQL. It is implemented as a
PL/pgSQL function and you can use it as a check constraint to validate the
format of your JSON columns.

postgres-json-schema supports the entire JSON schema draft v4 spec, except for
remote (http) references. It's tested against the official
[JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite).

# Installation

postgres-json-schema is packaged as an PGXS extension. To install, just run
`make install` as root, then `CREATE EXTENSION "postgres-json-schema";` as the
database superuser.

# Example

    CREATE TABLE example (id serial PRIMARY KEY, data jsonb);
    ALTER TABLE example ADD CONSTRAINT data_is_valid CHECK (validate_json_schema('{"type": "object"}', data));

    INSERT INTO example (data) VALUES ('{}');
    -- INSERT 0 1

    INSERT INTO example (data) VALUES ('1');
    -- ERROR:  new row for relation "example" violates check constraint "data_is_valid"
    -- DETAIL:  Failing row contains (2, 1).
