CREATE SCHEMA IF NOT EXISTS j;
    CREATE EXTENSION IF NOT EXISTS "postgres-json-schema" SCHEMA j;
    SET SEARCH_PATH TO j, public;

DO $f$
BEGIN
  ASSERT validate_json_schema('{}', '{}');
  ASSERT NOT validate_json_schema('{"type": "object"}', '1');
  ASSERT validate_json_schema('{"type": "object"}', '{}');
  ASSERT validate_json_schema('{"type": "number"}', '123.1');
  ASSERT validate_json_schema('{"type": "number"}', '123');
  ASSERT validate_json_schema('{"type": "integer"}', '123');
  ASSERT NOT validate_json_schema('{"type": "integer"}', '123.1');
  ASSERT validate_json_schema('{"type": "integer"}', '-103948');
  ASSERT NOT validate_json_schema('{"type": "number"}', '"a"');
  ASSERT validate_json_schema('{"type": "string"}', '"a"');
  ASSERT NOT validate_json_schema('{"type": "string"}', '{}');
  ASSERT validate_json_schema('{"type": "boolean"}', 'true');
  ASSERT NOT validate_json_schema('{"type": "boolean"}', 'null');
  ASSERT validate_json_schema('{"type": "null"}', 'null');
  ASSERT NOT validate_json_schema('{"type": "null"}', 'true');
  ASSERT validate_json_schema('{"type": "boolean"}', 'false');
  ASSERT NOT validate_json_schema('{"type": "boolean"}', '[]');
  ASSERT validate_json_schema('{"type": "array"}', '[]');
  ASSERT NOT validate_json_schema('{"type": "array"}', '1');

  ASSERT validate_json_schema('{"properties": {"foo": {"type": "string"}}}', '{"foo": "bar"}');
  ASSERT NOT validate_json_schema('{"properties": {"foo": {"type": "string"}}}', '{"foo": 1}');
  ASSERT validate_json_schema('{"properties": {"foo": {"type": "string"}}}', '{}');

  ASSERT validate_json_schema('{"required": ["foo"]}', '{"foo": 1}');
  ASSERT NOT validate_json_schema('{"required": ["foo"]}', '{"bar": 1}');

  ASSERT validate_json_schema('{"items": {"type": "integer"}}', '[1, 2, 3]');
  ASSERT NOT validate_json_schema('{"items": {"type": "integer"}}', '[1, 2, 3, "x"]');

  ASSERT validate_json_schema('{"minimum": 1.1}', '2.6');
  ASSERT NOT validate_json_schema('{"minimum": 1.1}', '0.6');
  ASSERT validate_json_schema('{"minimum": 12}', '12');

  ASSERT validate_json_schema('{"anyOf": [{"type": "integer"}, {"minimum": 2}]}', '1');
  ASSERT validate_json_schema('{"anyOf": [{"type": "integer"}, {"minimum": 2}]}', '2.5');
  ASSERT validate_json_schema('{"anyOf": [{"type": "integer"}, {"minimum": 2}]}', '3');
  ASSERT NOT validate_json_schema('{"anyOf": [{"type": "integer"}, {"minimum": 2}]}', '1.5');

  ASSERT validate_json_schema('{"uniqueItems": true}', '[1, 2]');
  ASSERT NOT validate_json_schema('{"uniqueItems": true}', '[1, 1]');

  ASSERT validate_json_schema('{"properties": {"foo": {}, "bar": {}}, "additionalProperties": false}', '{"foo": 1}');
  ASSERT NOT validate_json_schema('{"properties": {"foo": {}, "bar": {}}, "additionalProperties": false}', '{"foo" : 1, "bar" : 2, "quux" : "boom"}');

  ASSERT validate_json_schema('{"properties": {"foo": {"$ref": "#"}}, "additionalProperties": false}', '{"foo": false}');
  ASSERT validate_json_schema('{"properties": {"foo": {"$ref": "#"}}, "additionalProperties": false}', '{"foo": {"foo": false}}');
  ASSERT NOT validate_json_schema('{"properties": {"foo": {"$ref": "#"}}, "additionalProperties": false}', '{"bar": false}');
  ASSERT NOT validate_json_schema('{"properties": {"foo": {"$ref": "#"}}, "additionalProperties": false}', '{"foo": {"bar": false}}');

  ASSERT validate_json_schema('{"properties": {"foo": {"type": "integer"}, "bar": {"$ref": "#/properties/foo"}}}', '{"bar": 3}');
  ASSERT NOT validate_json_schema('{"properties": {"foo": {"type": "integer"}, "bar": {"$ref": "#/properties/foo"}}}', '{"bar": true}');

  ASSERT validate_json_schema('{"enum": [1,2,3]}', '1');
  ASSERT NOT validate_json_schema('{"enum": [1,2,3]}', '4');

END;
$f$ LANGUAGE 'plpgsql';


DO $f$
BEGIN
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://example.com:1234/hello/world.json#foo', 'http://example.com:1234', '/hello/world.json#foo') FROM json_schema_resolve_uri('#foo', 'http://example.com:1234', '/hello/world.json'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://example.com:1234/foo/prefix/hello/world', 'http://example.com:1234', '/foo/prefix/hello/world') FROM json_schema_resolve_uri('hello/world', 'http://example.com:1234', '/foo/prefix/'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://example.com:1234/foo/hello/world', 'http://example.com:1234', '/foo/hello/world') FROM json_schema_resolve_uri('hello/world', 'http://example.com:1234', '/foo/prefix'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://example.com:1234/hello/world', 'http://example.com:1234', '/hello/world') FROM json_schema_resolve_uri('http://crazy.com:1234/hello/world', 'http://example.com:1234', '/foo/prefix/'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://example.com:1234/hello/world', 'http://example.com:1234', '/hello/world') FROM json_schema_resolve_uri('http://example.com:1234/hello/world'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://example.com:1234/hello/world', 'http://example.com:1234', '/hello/world') FROM json_schema_resolve_uri('/hello/world', 'http://example.com:1234', '/foo/prefix'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://localhost:1234/nested.json#foo', 'http://localhost:1234', '/nested.json#foo') FROM json_schema_resolve_uri('http://localhost:1234/nested.json#foo', null, null));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://localhost:1234/nested.json#foo', 'http://localhost:1234', '/nested.json#foo') FROM json_schema_resolve_uri('http://localhost:1234/nested.json#foo'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('/hello/world', null, '/hello/world') FROM json_schema_resolve_uri('/hello/world'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('#foo', null, '#foo') FROM json_schema_resolve_uri('#foo'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('#foo', null, '#foo') FROM json_schema_resolve_uri('#foo'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://localhost:1234/sibling_id/base/foo.json', 'http://localhost:1234', '/sibling_id/base/foo.json') FROM json_schema_resolve_uri('foo.json', 'http://localhost:1234', '/sibling_id/base/'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('http://localhost:1234/sibling_id/foo.json', 'http://localhost:1234', '/sibling_id/foo.json') FROM json_schema_resolve_uri('foo.json', 'http://localhost:1234', '/sibling_id/base'));
    ASSERT (SELECT (resolved_uri, base_uri, base_path) IS NOT DISTINCT FROM ('urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar', 'urn:uuid:deadbeef-1234-0000-0000-4321feebdaed', '') FROM json_schema_resolve_uri('urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar'));
END;
$f$;


DO $f$
BEGIN
    ASSERT (SELECT (resolved_uri, resolved_path) = ('#foo', '{definitions,A}'::text[]) FROM json_schema_resolve_ids_to_paths('{"allOf": [{"$ref": "#foo"}], "definitions": {"A": {"id": "#foo", "type": "integer"}}}'));
    ASSERT (SELECT jsonb_object_agg(resolved_uri, resolved_path) = '{"http://example.com/schema-relative-uri-defs1.json": [], "http://example.com/schema-relative-uri-defs2.json": ["properties", "foo"]}' FROM json_schema_resolve_ids_to_paths('{"$id": "http://example.com/schema-relative-uri-defs1.json", "properties": {"foo": {"$id": "schema-relative-uri-defs2.json", "definitions": {"inner": {"properties": {"bar": {"type": "string"}}}}, "allOf": [{"$ref": "#/definitions/inner"}]}}, "allOf": [{"$ref": "schema-relative-uri-defs2.json"}]}'));
    ASSERT (SELECT jsonb_object_agg(resolved_uri, resolved_path) = '{"http://localhost:1234/sibling_id/": ["allOf", "0"], "http://localhost:1234/sibling_id/base/": [], "http://localhost:1234/sibling_id/foo.json": ["definitions", "foo"], "http://localhost:1234/sibling_id/base/foo.json": ["definitions", "base_foo"]}' FROM json_schema_resolve_ids_to_paths('{"id": "http://localhost:1234/sibling_id/base/", "definitions": {"foo": {"id": "http://localhost:1234/sibling_id/foo.json", "type": "string"}, "base_foo": {"$comment": "this canonical uri is http://localhost:1234/sibling_id/base/foo.json", "id": "foo.json", "type": "number"}}, "allOf": [{"$comment": "$ref resolves to http://localhost:1234/sibling_id/base/foo.json, not http://localhost:1234/sibling_id/foo.json", "id": "http://localhost:1234/sibling_id/", "$ref": "foo.json"}]}'));
    ASSERT (SELECT jsonb_object_agg(resolved_uri, resolved_path) = '{"http://localhost:1234/root": [], "http://localhost:1234/nested.json": ["definitions", "A"], "http://localhost:1234/nested.json#foo": ["definitions", "A", "definitions", "B"]}' FROM json_schema_resolve_ids_to_paths('{"$id": "http://localhost:1234/root", "allOf": [{"$ref": "http://localhost:1234/nested.json#foo"}], "definitions": {"A": {"$id": "nested.json", "definitions": {"B": {"$id": "#foo", "type": "integer"}}}}}'));
    ASSERT (SELECT jsonb_object_agg(resolved_uri, resolved_path) = '{"urn:uuid:deadbeef-1234-0000-0000-4321feebdaed": []}' FROM json_schema_resolve_ids_to_paths('{"$id": "urn:uuid:deadbeef-1234-0000-0000-4321feebdaed", "properties": {"foo": {"$ref": "urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar"}}, "$defs": {"bar": {"type": "string"}}}'));
END;
$f$;


DO $f$
BEGIN
    ASSERT (SELECT a->'properties'->'foo'->'allOf'->0->'$_resolvedRef' = '["properties", "foo", "definitions", "inner"]' FROM json_schema_resolve_refs('{"$id": "http://example.com/schema-relative-uri-defs1.json", "properties": {"foo": {"$id": "schema-relative-uri-defs2.json", "definitions": {"inner": {"properties": {"bar": {"type": "string"}}}}, "allOf": [{"$ref": "#/definitions/inner"}]}}, "allOf": [{"$ref": "schema-relative-uri-defs2.json"}]}') a);
    ASSERT (SELECT a->'properties'->'properties'->'allOf'->0->'$_resolvedRef' = '["properties", "properties", "definitions", "inner"]' FROM json_schema_resolve_refs('{"$id": "http://example.com/schema-relative-uri-defs1.json", "properties": {"properties": {"$id": "schema-relative-uri-defs2.json", "definitions": {"inner": {"properties": {"bar": {"type": "string"}}}}, "allOf": [{"$ref": "#/definitions/inner"}]}}, "allOf": [{"$ref": "schema-relative-uri-defs2.json"}]}') a);
    ASSERT (SELECT a->'allOf'->0->'$_resolvedRef' = '["definitions", "base_foo"]'::jsonb FROM json_schema_resolve_refs('{"id": "http://localhost:1234/sibling_id/base/", "definitions": {"foo": {"id": "http://localhost:1234/sibling_id/foo.json", "type": "string"}, "base_foo": {"$comment": "this canonical uri is http://localhost:1234/sibling_id/base/foo.json", "id": "foo.json", "type": "number"}}, "allOf": [{"$comment": "$ref resolves to http://localhost:1234/sibling_id/base/foo.json, not http://localhost:1234/sibling_id/foo.json", "id": "http://localhost:1234/sibling_id/", "$ref": "foo.json"}]}') a);

    ASSERT (SELECT '{"type": "array", "items": [{"$ref": "#/definitions/item", "$_resolvedRef": ["definitions", "item"]}, {"$ref": "#/definitions/item", "$_resolvedRef": ["definitions", "item"]}, {"$ref": "#/definitions/item", "$_resolvedRef": ["definitions", "item"]}], "definitions": {"item": {"type": "array", "items": [{"$ref": "#/definitions/sub-item", "$_resolvedRef": ["definitions", "sub-item"]}, {"$ref": "#/definitions/sub-item", "$_resolvedRef": ["definitions", "sub-item"]}], "additionalItems": false}, "sub-item": {"type": "object", "required": ["foo"]}}, "additionalItems": false}'::jsonb = json_schema_resolve_refs('{"definitions": {"item": {"type": "array", "additionalItems": false, "items": [{"$ref": "#/definitions/sub-item"}, {"$ref": "#/definitions/sub-item"}]}, "sub-item": {"type": "object", "required": ["foo"]}}, "type": "array", "additionalItems": false, "items": [{"$ref": "#/definitions/item"}, {"$ref": "#/definitions/item"}, {"$ref": "#/definitions/item"}]}'));
    ASSERT (SELECT '{"$id": "http://localhost:1234/tree", "type": "object", "required": ["meta", "nodes"], "properties": {"meta": {"type": "string"}, "nodes": {"type": "array", "items": {"$ref": "node", "$_resolvedRef": ["definitions", "node"]}}}, "definitions": {"node": {"$id": "http://localhost:1234/node", "type": "object", "required": ["value"], "properties": {"value": {"type": "number"}, "subtree": {"$ref": "tree", "$_resolvedRef": []}}, "description": "node"}}, "description": "tree of nodes"}'::jsonb = json_schema_resolve_refs('{"$id": "http://localhost:1234/tree", "description": "tree of nodes", "type": "object", "properties": {"meta": {"type": "string"}, "nodes": {"type": "array", "items": {"$ref": "node"}}}, "required": ["meta", "nodes"], "definitions": {"node": {"$id": "http://localhost:1234/node", "description": "node", "type": "object", "properties": {"value": {"type": "number"}, "subtree": {"$ref": "tree"}}, "required": ["value"]}}}'));

    ASSERT (SELECT json_schema_resolve_refs('{"properties": {"$ref": {"type": "string"}}}') = '{"properties": {"$ref": {"type": "string"}}}');
    ASSERT (SELECT json_schema_resolve_refs('{"allOf": [{"$ref": "#foo"}], "definitions": {"A": {"id": "#foo", "type": "integer"}}}') = '{"allOf": [{"$ref": "#foo", "$_resolvedRef": ["definitions", "A"]}], "definitions": {"A": {"id": "#foo", "type": "integer"}}}');

    ASSERT (SELECT json_schema_resolve_refs('{"allOf": [{"$ref": "#/definitions/bool"}], "definitions": {"bool": true}}') = '{"allOf": [{"$ref": "#/definitions/bool", "$_resolvedRef": ["definitions", "bool"]}], "definitions": {"bool": true}}');
    ASSERT (SELECT json_schema_resolve_refs('{"properties": {"$ref": {"$ref": "#/definitions/is-string"}}, "definitions": {"is-string": {"type": "string"}}}') = '{"properties": {"$ref": {"$ref": "#/definitions/is-string", "$_resolvedRef": ["definitions", "is-string"]}}, "definitions": {"is-string": {"type": "string"}}}');

    ASSERT (SELECT json_schema_resolve_refs('{"$id": "urn:uuid:deadbeef-1234-0000-0000-4321feebdaed", "properties": {"foo": {"$ref": "urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar"}}, "$defs": {"bar": {"type": "string"}}}') = '{"$id": "urn:uuid:deadbeef-1234-0000-0000-4321feebdaed", "$defs": {"bar": {"type": "string"}}, "properties": {"foo": {"$ref": "urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar", "$_resolvedRef": ["$defs", "bar"]}}}');

    ASSERT (SELECT json_schema_resolve_refs('{"properties": {"foo": {"$ref": "#"}}, "additionalProperties": false}') = '{"properties": {"foo": {"$ref": "#", "$_resolvedRef": []}}, "additionalProperties": false}');

    ASSERT (SELECT json_schema_resolve_refs('{"properties": {"$ref": {"type": "string"}}}') = '{"properties": {"$ref": {"type": "string"}}}');
END;
$f$;


DO $f$
BEGIN
    ASSERT (SELECT '{foo}'::text[] = json_schema_resolve_ref('#foo', null, null, null));
    ASSERT (SELECT '{definitions,item}'::text[] = json_schema_resolve_ref('#/definitions/item', null, null, null));
    ASSERT (SELECT '{}'::text[] = json_schema_resolve_ref('#', null, null, null));
    ASSERT (SELECT '{definitions,base_foo}'::text[] = json_schema_resolve_ref('foo.json', 'http://localhost:1234', '/sibling_id/base/', '{"http://localhost:1234/sibling_id/base/foo.json": ["definitions","base_foo"]}'));
    ASSERT (SELECT '{$defs,bar}'::text[] = json_schema_resolve_ref('urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar', null, null, '{"urn:uuid:deadbeef-1234-0000-0000-4321feebdaed": []}'));
    ASSERT (SELECT '{definitions,A,definitions,B,part1,nested}'::text[] = json_schema_resolve_ref('http://localhost:1234/nested.json#foo/part1/nested', NULL, NULL, '{"http://localhost:1234/root": [], "http://localhost:1234/nested.json": ["definitions", "A"], "http://localhost:1234/nested.json#foo": ["definitions", "A", "definitions", "B"]}'));
END;
$f$;


CREATE OR REPLACE FUNCTION test_raises_exception(
    text,
    expected jsonb,
    OUT result bool, OUT msg text
) AS $f$
    DECLARE
        RETURNED_SQLSTATE text;
        COLUMN_NAME text;
        CONSTRAINT_NAME text;
        PG_DATATYPE_NAME text;
        MESSAGE_TEXT text;
        TABLE_NAME text;
        SCHEMA_NAME text;
        PG_EXCEPTION_DETAIL text;
        PG_EXCEPTION_HINT text;
        PG_EXCEPTION_CONTEXT text;
        v_vars jsonb;
        v_key text;
        v_value text;
    BEGIN
        result := false;
        msg := 'No exception raised';
        execute ( $1 );
    EXCEPTION
        WHEN others THEN
            GET STACKED DIAGNOSTICS
                RETURNED_SQLSTATE := RETURNED_SQLSTATE,
                COLUMN_NAME := COLUMN_NAME,
                CONSTRAINT_NAME := CONSTRAINT_NAME,
                PG_DATATYPE_NAME := PG_DATATYPE_NAME,
                MESSAGE_TEXT := MESSAGE_TEXT,
                TABLE_NAME := TABLE_NAME,
                SCHEMA_NAME := SCHEMA_NAME,
                PG_EXCEPTION_DETAIL := PG_EXCEPTION_DETAIL,
                PG_EXCEPTION_HINT := PG_EXCEPTION_HINT,
                PG_EXCEPTION_CONTEXT := PG_EXCEPTION_CONTEXT;

            v_vars := jsonb_build_object(
                'RETURNED_SQLSTATE', RETURNED_SQLSTATE,
                'COLUMN_NAME', COLUMN_NAME,
                'CONSTRAINT_NAME', CONSTRAINT_NAME,
                'PG_DATATYPE_NAME', PG_DATATYPE_NAME,
                'MESSAGE_TEXT', MESSAGE_TEXT,
                'TABLE_NAME', TABLE_NAME,
                'SCHEMA_NAME', SCHEMA_NAME,
                'PG_EXCEPTION_DETAIL', PG_EXCEPTION_DETAIL,
                'PG_EXCEPTION_HINT', PG_EXCEPTION_HINT,
                'PG_EXCEPTION_CONTEXT', PG_EXCEPTION_CONTEXT
            );
            IF expected IS NOT NULL THEN
                FOR v_key, v_value IN SELECT k, coalesce(expected->>k, expected->>lower(k)) FROM jsonb_object_keys(v_vars) k LOOP

                    IF v_value IS NOT NULL AND v_vars->>v_key NOT ILIKE v_value THEN
                        result := false;
                        msg := format('%s: %s != Expected %s', v_key, v_vars->>v_key, v_value);
                        RETURN;
                    END IF;
                END LOOP;
            END IF;

            result := true;
            msg := MESSAGE_TEXT;
    END;

$f$ LANGUAGE plpgsql VOLATILE ;



DO $f$
BEGIN
    ASSERT (SELECT true = null::json_schema_validation_result::bool);
    ASSERT (SELECT true = (null)::json_schema_validation_result::bool);
    ASSERT (SELECT true = (null, null)::json_schema_validation_result::bool);
    ASSERT (SELECT true = ('{path,to,field}', null)::json_schema_validation_result::bool);

    ASSERT ( SELECT result FROM test_raises_exception( $$ SELECT true = null::json_schema_validation_result $$, '{"message_text":  "operator does not exist: boolean = json_schema_validation_result"}' ) );
    ASSERT ( SELECT result FROM test_raises_exception( $$ SELECT true = ARRAY[(null)::json_schema_validation_result] $$, '{"message_text":  "operator does not exist: boolean = json_schema_validation_result[]"}' ) );

    ASSERT (SELECT NOT (NOT NULL::json_schema_validation_result));
    ASSERT (SELECT NOT (NOT NULL::json_schema_validation_result));
    ASSERT (SELECT NOT ('{path,to,field}', 'FAILED')::json_schema_validation_result);
    ASSERT (SELECT NOT ARRAY[('{path,to,field}', 'FAILED')]::json_schema_validation_result[]);
    ASSERT (SELECT NOT ARRAY[('{path,to,field}', 'FAILED')]::json_schema_validation_result[]);
    ASSERT (SELECT NOT ARRAY[NULL, ('{path,to,field}', 'FAILED')]::json_schema_validation_result[]);
    ASSERT (SELECT ARRAY[NULL]::json_schema_validation_result[]);
    ASSERT (SELECT ARRAY[('{path,to,field}', null)]::json_schema_validation_result[]::bool);
    ASSERT (SELECT NULL::json_schema_validation_result[]::bool);

END;
$f$;


DO $f$
DECLARE
    v_result RECORD;
    v_schema1 jsonb := $$ {
            "definitions": {
                "reffed": {
                    "type": "array"
                }
            },
            "properties": {
                "foo": {
                    "$ref": "#/definitions/reffed",
                    "maxItems": 2
                }
            }
        } $$;

    v_schema2 jsonb := $${
            "definitions": {
                "reffed": {
                    "type": "array"
                }
            },
            "properties": {
                "foo": {
                    "type": "array",
                    "maxItems": 2,
                    "items": {
                      "type": "number"
                    }
                }
            }
        } $$;
BEGIN

    SELECT INTO v_result *, ARRAY[('{foo}','string is not a valid type: {array}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations(v_schema1, $$ { "foo": "string" } $$) a;
        ASSERT v_result.valid, v_result;
    SELECT INTO v_result *, ARRAY[('{foo}','items count of 3 exceeds maxItems of 2')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations(v_schema1, $$ { "foo": ["string", "23", 1] } $$) a;
        ASSERT v_result.valid, v_result;
    SELECT INTO v_result *, ARRAY[]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations(v_schema1, $$ { "foo": ["string", 1] } $$) a;
        ASSERT v_result.valid, v_result;
    SELECT INTO v_result *, ARRAY[('{1}','string is not a valid type: {integer}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"items": [{"type": "integer"}, {"$ref": "#/items/0"}]}', '[1, "foo"]') a;
        ASSERT v_result.valid, v_result;
    SELECT INTO v_result *, ARRAY[('{foo,0}','string is not a valid type: {number}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations(v_schema2, $$ { "foo": ["hello"] } $$) a;
        ASSERT v_result.valid, v_result;
    -- test string is not valid even if it is all digits when string_as_number is false
    SELECT INTO v_result *, ARRAY[('{foo,0}','string is not a valid type: {number}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations(v_schema2, $$ { "foo": ["0"] } $$) a;
        ASSERT v_result.valid, v_result;
    -- test quoted number is valid when string_as_number is true with a literal string
    SELECT INTO v_result *, ARRAY[]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"type": "number"}', $$"1"$$, true) a;
        ASSERT v_result.valid, v_result;
    -- test quoted number is valid when string_as_number is true with a literal decimal string
    SELECT INTO v_result *, ARRAY[]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"type": "number"}', $$"1.1"$$, true) a;
        ASSERT v_result.valid, v_result;
    -- test quoted number is valid when string_as_number is true with an object
    SELECT INTO v_result *, ARRAY[]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"properties":  {"foo": {"type": "number"}}}', $${ "foo": "1" }$$, true) a;
        ASSERT v_result.valid, v_result;
    -- test quoted number is valid when string_as_number is true with an array
    SELECT INTO v_result *, ARRAY[]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations(v_schema2, $$ { "foo": ["0"] } $$, true) a;
        ASSERT v_result.valid, v_result;

    -- test quoted number when string_as_number is true with a invalid numerical string
    SELECT INTO v_result *, ARRAY[('{}', 'string is not a valid type: {number}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"type": "number"}', $$".1"$$, true) a;
        ASSERT v_result.valid, v_result;

    -- test quoted number when string_as_number is true with a invalid numerical string
    SELECT INTO v_result *, ARRAY[('{}', 'string is not a valid type: {number}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"type": "number"}', $$"0.1.1"$$, true) a;
        ASSERT v_result.valid, v_result;

    -- test quoted integer is not valid even when string_as_number is true
    SELECT INTO v_result *, ARRAY[('{1}','string is not a valid type: {integer}')]::json_schema_validation_result[] = a AS valid FROM get_json_schema_validations('{"items": [{"type": "integer"}, {"$ref": "#/items/0"}]}', '[1, "1"]', true) a;
        ASSERT v_result.valid, v_result;

    v_result := test_raises_exception(format($$ SELECT json_schema_check_constraint (%L, '{ "foo": ["string", 1, "Too many items here"] }') $$, v_schema1), '{"message_text":  "json_schema_validation_failed", "PG_EXCEPTION_DETAIL": [{"path": ["foo"], "error": "items count of 3 exceeds maxItems of 2"}]}');
    ASSERT v_result.result = true, v_result;
    -- does not raise any exception for valid string
    ASSERT true = json_schema_check_constraint('{"type": "number"}', '"1.9"', true);

    -- create the table
    EXECUTE format($$ CREATE TEMPORARY TABLE test_entry (data jsonb CHECK ( validate_json_schema(%L, data) )) ON COMMIT DROP$$, v_schema1);
    -- valid data
    INSERT INTO test_entry VALUES ('{ "foo": ["string", 1] }');
    -- invalid data
    v_result := test_raises_exception($$ INSERT INTO test_entry VALUES ('{ "foo": ["string", 1, "Too many items here"] }') $$, '{"message_text":  "new row for relation \"test_entry\" violates check constraint \"test_entry_data_check\""}');
    ASSERT v_result.result = true, v_result;

    -- Create the table
    EXECUTE format($$ CREATE TEMPORARY TABLE test_entry_with_detailed_message (data jsonb CHECK ( json_schema_check_constraint(%L, data) )) ON COMMIT DROP$$, v_schema1);
    -- test valid data
    INSERT INTO test_entry_with_detailed_message VALUES ('{ "foo": ["string", 1] }');
    -- test invalid data

    v_result := test_raises_exception($$ INSERT INTO test_entry_with_detailed_message VALUES ('{ "foo": ["string", 1, "Too many items here"] }') $$, '{"message_text": "json_schema_validation_failed", "PG_EXCEPTION_DETAIL": [{"path": ["foo"], "error": "items count of 3 exceeds maxItems of 2"}] }' );
    ASSERT v_result.result = true, v_result;

END
$f$;
