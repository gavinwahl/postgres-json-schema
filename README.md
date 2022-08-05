# postgres-json-schema

[![Build Status](https://travis-ci.org/gavinwahl/postgres-json-schema.svg?branch=master)](https://travis-ci.org/gavinwahl/postgres-json-schema)

postgres-json-schema allows validation of [JSON
schemas](http://json-schema.org/) in PostgreSQL. It is implemented as a
PL/pgSQL function and you can use it as a check constraint to validate the
format of your JSON columns.

postgres-json-schema supports the entire JSON schema draft v4 and v7 spec, except for
remote (http) references. It's tested against the official
[JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite).

# Installation

postgres-json-schema is packaged as an PGXS extension. To install, just run
`make install` as root, then `CREATE EXTENSION "postgres-json-schema";` as the
database superuser.

# Usage

## Types
- `json_schema_validation_result` A composite type which contains error messages and path (an array to the path) within json data where the validation failed
  #### contains the following attributes
  - `path` a `text[]` to the path where the validation failed
  - `error` the validation error message

## Functions

####  Functions accepting a argument `string_as_number` controlling whether a schema expecting a number may contain a valid number as a string. This is useful when dealing with for example python Decimal, which most implementations serialize it to json as a quoted string not to lose decimal precision.

- ```sql
  -- Returns bool
  validate_json_schema(schema jsonb, data jsonb, string_as_number bool)
  ```
- ```sql
  -- Returns ARRAY json_schema_validation_result[]
  get_json_schema_validations(schema jsonb, data jsonb, string_as_number bool)
  ```
- ```sql
  -- Returns true if valid,
  -- otherwise raises a check_constraint exception, this is useful when you want to get a detailed
  -- error knowing which part of the json document failed to validate.
  json_schema_check_constraint(
    schema jsonb,
    data jsonb,
    string_as_number bool default false,
    table_name text default '', -- if you need to set the value for TABLE in the PG_EXCEPTION_CONTEXT
    column_name text default '' -- if you need to set the value for COLUMN in the PG_EXCEPTION_CONTEXT
  )
  ```
- `json_schema_resolve_refs( schema )`

  When dealing with a JSON schema that has `$id` uri values being used in `$ref`,
  there is a convenient function to resolve those references
  ```sql
  validate_json_schema( json_schema_resolve_refs( schema ), data );
  -- or
  json_schema_check_constraint( json_schema_resolve_refs( schema ), data, ... );
  ```


# Example

#### Using standard default check constraint with boolean function
```sql
CREATE TABLE example (id serial PRIMARY KEY, data jsonb);
ALTER TABLE example ADD CONSTRAINT data_is_valid CHECK (validate_json_schema('{"type": "object"}', data));

INSERT INTO example (data) VALUES ('{}');
-- INSERT 0 1

INSERT INTO example (data) VALUES ('1');
-- ERROR:  new row for relation "example" violates check constraint "data_is_valid"
-- DETAIL:  Failing row contains (2, 1).
```


#### Using custom check constraint exception with detailed error
```sql
CREATE TABLE example (id serial PRIMARY KEY, data jsonb);
ALTER TABLE example ADD CONSTRAINT data_is_valid CHECK (json_schema_check_constraint('{"type": "object", "properties": { "foo": {"type": "number"}, "bar": { "prefixItems": [{ "type": "number" }, { "type": "number", "minimum": 2 }] } }}', data, true, table_name := 'example', column_name := 'data'));

INSERT INTO example (data) VALUES ('{}');
-- INSERT 0 1

INSERT INTO example (data) VALUES ('1');
-- ERROR:  json_schema_validation_failed
-- DETAIL:  [{"path": [], "error": "number is not a valid type: {object}"}]
-- CONTEXT:  PL/pgSQL function json_schema_check_constraint(jsonb,jsonb,boolean,text,text) line 7 at RAISE

INSERT INTO example (data) VALUES ('{ "foo": "string" }');
-- ERROR:  json_schema_validation_failed
-- DETAIL:  [{"path": ["foo"], "error": "string is not a valid type: {number}"}]
-- CONTEXT:  PL/pgSQL function json_schema_check_constraint(jsonb,jsonb,boolean,text,text) line 7 at RAISE

INSERT INTO example (data) VALUES ('{ "foo": 1, "bar": ["a", 1.1] }');
-- ERROR:  json_schema_validation_failed
-- DETAIL:  [{"path": ["bar", "0"], "error": "string is not a valid type: {number}"}, {"path": ["bar", "1"], "error": "value must be >= 2"}]
-- CONTEXT:  PL/pgSQL function json_schema_check_constraint(jsonb,jsonb,boolean,text,text) line 7 at RAISE
```
