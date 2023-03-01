CREATE TYPE json_schema_validation_result AS (
    path text[],
    error text
);


CREATE OR REPLACE FUNCTION json_schema_validation_result_as_bool (@extschema@.json_schema_validation_result) RETURNS bool AS $$
    SELECT ($1).error IS NULL;
$$ LANGUAGE SQL IMMUTABLE;

CREATE CAST ( json_schema_validation_result AS bool )
    WITH FUNCTION @extschema@.json_schema_validation_result_as_bool(json_schema_validation_result)
    AS ASSIGNMENT;

CREATE OR REPLACE FUNCTION json_schema_validation_result_array_as_bool (@extschema@.json_schema_validation_result[]) RETURNS bool AS $$
    SELECT $1 IS NULL OR true = ALL ($1::bool[]);
$$ LANGUAGE SQL IMMUTABLE;


CREATE CAST ( json_schema_validation_result[] AS bool )
    WITH FUNCTION @extschema@.json_schema_validation_result_array_as_bool(json_schema_validation_result[])
    AS ASSIGNMENT;



CREATE OR REPLACE FUNCTION urldecode_arr(url text) RETURNS text AS $BODY$
    DECLARE
        ret text;
    BEGIN
        BEGIN
            WITH str AS (
                SELECT
                -- array with all non encoded parts, prepend with '' when the string start is encoded
                CASE WHEN $1 ~ '^%[0-9a-fA-F][0-9a-fA-F]' THEN
                    ARRAY ['']
                END || regexp_split_to_array($1, '(%[0-9a-fA-F][0-9a-fA-F])+', 'i') plain,

                -- array with all encoded parts
                ARRAY(select (regexp_matches($1, '((?:%[0-9a-fA-F][0-9a-fA-F])+)', 'gi'))[1]) encoded
            )
            SELECT string_agg(plain[i] || coalesce(convert_from(decode(replace(encoded[i], '%', ''), 'hex'), 'utf8'), ''), '')
            FROM str, (SELECT generate_series(1, array_upper(encoded, 1) + 2) i FROM str) blah
            INTO ret;

        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'failed: %', url;
                RETURN $1;
        END;

        RETURN coalesce(ret, $1); -- when the string has no encoding;

    END;
$BODY$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION _validate_json_schema_type(type text, data jsonb, string_as_number bool default false) RETURNS boolean AS $f$
BEGIN
  IF type = 'integer' THEN
    IF jsonb_typeof(data) != 'number' THEN
      RETURN false;
    END IF;
    IF trunc(data::text::numeric) != data::text::numeric THEN
      RETURN false;
    END IF;
  ELSEIF type = 'number' AND jsonb_typeof(data) = 'string' THEN
    IF NOT string_as_number OR NOT data @? '$ ? (@ like_regex "^\\d+(\\.\\d+)?$")'::jsonpath THEN
      RETURN false;
    END IF;
  ELSE
    IF type != jsonb_typeof(data) THEN
      RETURN false;
    END IF;
  END IF;
  RETURN true;
END;
$f$ LANGUAGE 'plpgsql' IMMUTABLE;


-- MOCK Placeholder
CREATE OR REPLACE FUNCTION get_json_schema_validations(schema jsonb, data jsonb, root_schema jsonb, schema_path text[], string_as_number bool)
RETURNS json_schema_validation_result[] AS $f$ BEGIN END; $f$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_json_schema_validations(schema jsonb, data jsonb, string_as_number bool DEFAULT false)
RETURNS json_schema_validation_result[] AS $f$
    SELECT @extschema@.get_json_schema_validations(schema, data, schema, ARRAY []::text[], string_as_number);
$f$ LANGUAGE SQL IMMUTABLE ;

CREATE OR REPLACE FUNCTION validate_json_schema(schema jsonb, data jsonb, string_as_number bool) RETURNS bool AS $f$
    SELECT @extschema@.get_json_schema_validations(schema, data, schema, ARRAY []::text[], string_as_number)::bool;
$f$ LANGUAGE SQL IMMUTABLE ;

CREATE OR REPLACE FUNCTION validate_json_schema(schema jsonb, data jsonb, root_schema jsonb DEFAULT null, string_as_number bool DEFAULT false) RETURNS bool AS $f$
    SELECT @extschema@.get_json_schema_validations(schema, data, root_schema, ARRAY []::text[], string_as_number)::bool;
$f$ LANGUAGE SQL IMMUTABLE ;

CREATE OR REPLACE FUNCTION json_schema_check_constraint(
    schema jsonb,
    data jsonb,
    string_as_number bool default false,
    table_name text default '',
    column_name text default ''
) RETURNS bool AS $$
    DECLARE
        result json_schema_validation_result[];
    BEGIN
        result := @extschema@.get_json_schema_validations(schema, data, schema, '{}'::text[], string_as_number := string_as_number);
        IF (NOT result) THEN
            RAISE check_violation USING
                MESSAGE = 'json_schema_validation_failed',
                DETAIL = to_jsonb(result),
                -- HINT = v_value,
                TABLE = table_name,
                COLUMN = column_name;
        END IF;
        RETURN true;
    END;
$$ LANGUAGE plpgsql IMMUTABLE ;



CREATE OR REPLACE FUNCTION _validate_json_multiple_schemas(
    schemas_array jsonb, data jsonb, root_schema jsonb, schema_path text[], string_as_number bool,
    OUT validation_booleans bool[],
    OUT all_errors @extschema@.json_schema_validation_result[]
) AS $f$
    WITH schema_validations AS (
        SELECT q FROM jsonb_array_elements(schemas_array) sub_schema,
                     @extschema@.get_json_schema_validations(sub_schema, data, root_schema, schema_path, string_as_number) q
    )
    SELECT
          (SELECT array_agg(q::bool) FROM schema_validations t(q)) AS validation_booleans,
          (SELECT array_agg(v) FILTER ( WHERE NOT v) FROM schema_validations t(q), unnest(q) v) AS all_errors
$f$ LANGUAGE SQL IMMUTABLE ;


CREATE OR REPLACE FUNCTION get_json_schema_validations(schema jsonb, data jsonb, root_schema jsonb, schema_path text[], string_as_number bool)
RETURNS @extschema@.json_schema_validation_result[] AS $f$
DECLARE
  prop text;
  item jsonb;
  idx int;
  path text[];
  types text[];
  prefixItems jsonb;
  additionalItems jsonb;
  pattern text;
  props text[];
  result @extschema@.json_schema_validation_result[];
  q_result record;
BEGIN
  IF root_schema IS NULL THEN
    root_schema = schema;
  END IF;

  IF schema IS NULL THEN
    RETURN ARRAY [(schema_path, format('NULL schema: [data: %s]', data))];
  END IF;

  IF jsonb_typeof(schema) = 'boolean' THEN
      IF schema = 'true'::jsonb THEN
        RETURN NULL; -- anything is valid
      ELSEIF schema = 'false'::jsonb THEN
        RETURN ARRAY [(schema_path, format('"false" does not accept any value received "%s"', data))]; -- anything is valid
      ELSEIF schema != data THEN
        RETURN ARRAY [(schema_path, format('%s does not match %s', data, schema))];
      END IF;
  END IF;

  IF schema ? 'type' THEN
    IF jsonb_typeof(schema->'type') = 'array' THEN
      types = ARRAY(SELECT jsonb_array_elements_text(schema->'type'));
    ELSE
      types = ARRAY[schema->>'type'];
    END IF;
    IF (SELECT NOT bool_or(@extschema@._validate_json_schema_type(type, data, string_as_number)) FROM unnest(types) type) THEN
      RETURN ARRAY [(schema_path, format('%s is not a valid type: %s', jsonb_typeof(data), types))];
    END IF;
  END IF;

  IF schema ? 'properties' THEN
    FOR prop IN SELECT jsonb_object_keys(schema->'properties') LOOP
      IF data ? prop THEN
        result := @extschema@.get_json_schema_validations(schema->'properties'->prop, data->prop, root_schema, schema_path || prop, string_as_number);
        IF NOT result THEN
            RETURN result;
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF schema ? 'required' AND jsonb_typeof(data) = 'object' THEN
    IF NOT ARRAY(SELECT jsonb_object_keys(data)) @>
           ARRAY(SELECT jsonb_array_elements_text(schema->'required')) THEN
      RETURN ARRAY [(schema_path, format('%s is missing required properties: %s', schema->>'type', ARRAY(
          SELECT jsonb_array_elements_text(schema->'required')
          EXCEPT
          SELECT jsonb_object_keys(data)
          )))];
    END IF;
  END IF;

  /*
   In 2019 items could be any of [boolean, object]
   In draft6 items could be [boolean, object, array]
   In draft4 items could be either a [object, array]
   */
  IF jsonb_typeof(data) = 'array' THEN
      IF schema ? 'prefixItems' THEN
          -- jsonschema 2019
          prefixItems := schema->'prefixItems';
          IF schema ? 'items' THEN
              additionalItems := schema->'items';
          ELSEIF schema ? 'additionalItems' THEN
              additionalItems := schema->'additionalItems';
          END IF;
      ELSEIF schema ? 'items' THEN
          IF jsonb_typeof(schema->'items') = 'object' THEN
            additionalItems := schema->'items';
          ELSEIF jsonb_typeof(schema->'items') = 'array' THEN
            prefixItems := schema->'items';
            additionalItems := schema->'additionalItems';
          ELSEIF jsonb_typeof(schema->'items') = 'boolean' THEN
            additionalItems := schema->'items';
          END IF;
      END IF;

      IF prefixItems IS NOT NULL THEN
        SELECT array_agg(q) INTO result
                            FROM jsonb_array_elements(prefixItems) WITH ORDINALITY AS t(sub_schema, i),
                                 @extschema@.get_json_schema_validations(sub_schema, data->(i::int - 1), root_schema, schema_path || (i - 1)::text, string_as_number) q1, unnest(q1) q
                            WHERE i <= jsonb_array_length(data);
        IF NOT result THEN
          RETURN result;
        END IF;

      END IF;

      IF jsonb_typeof(additionalItems) = 'boolean' and NOT (additionalItems)::text::boolean THEN
        IF jsonb_array_length(data) > COALESCE(jsonb_array_length(prefixItems), 0) THEN
          RETURN ARRAY [(schema_path, format('field only accepts %s items', COALESCE(jsonb_array_length(prefixItems), 0)))];
        END IF;
      END IF;

      IF jsonb_typeof(additionalItems) = 'object' THEN
        SELECT array_agg(q) INTO result
        FROM jsonb_array_elements(data) WITH ORDINALITY AS t(elem, i),
             @extschema@.get_json_schema_validations(additionalItems, elem, root_schema, schema_path || (i - 1)::text, string_as_number) AS  q1, unnest(q1) q
        WHERE i > coalesce(jsonb_array_length(prefixItems), 0) AND NOT q LIMIT 1;

        IF NOT result THEN
            RETURN result;
        END IF;
      END IF;
  END IF;


  IF schema ? 'minimum' AND jsonb_typeof(data) = 'number' THEN
    IF data::text::numeric < (schema->>'minimum')::numeric THEN
      RETURN ARRAY [(schema_path, format('value must be >= %s', (schema->>'minimum')))];
    END IF;
  END IF;

  IF schema ? 'maximum' AND jsonb_typeof(data) = 'number' THEN
    IF data::text::numeric > (schema->>'maximum')::numeric THEN
      RETURN ARRAY [(schema_path, format('value must be <= %s', (schema->>'maximum')))];
    END IF;
  END IF;

  IF schema ? 'exclusiveMinimum' AND jsonb_typeof(data) = 'number' THEN
      IF jsonb_typeof(schema->'exclusiveMinimum') = 'number' THEN
        IF data::text::numeric <= (schema->>'exclusiveMinimum')::numeric THEN
          RETURN ARRAY [(schema_path, format('value must be > %s', (schema->>'exclusiveMinimum')))];
        END IF;
      ELSEIF COALESCE((schema->'exclusiveMinimum')::text::bool, FALSE) THEN
        IF data::text::numeric = (schema->>'minimum')::numeric THEN
          RETURN ARRAY [(schema_path, format('value must be > %s', (schema->>'minimum')))];
        END IF;
      END IF;
  END IF;

  IF schema ? 'exclusiveMaximum' AND jsonb_typeof(data) = 'number' THEN
      IF jsonb_typeof(schema->'exclusiveMaximum') = 'number' THEN
        IF data::text::numeric >= (schema->>'exclusiveMaximum')::numeric THEN
          RETURN ARRAY [(schema_path, format('value must be < %s', (schema->>'exclusiveMinimum')))];
        END IF;
      ELSEIF COALESCE((schema->'exclusiveMaximum')::text::bool, FALSE) THEN
        IF data::text::numeric = (schema->>'maximum')::numeric THEN
          RETURN ARRAY [(schema_path, format('value must be < %s', (schema->>'maximum')))];
        END IF;
      END IF;
  END IF;

  IF schema ? 'anyOf' THEN
    q_result := @extschema@._validate_json_multiple_schemas(schema->'anyOf', data, root_schema, schema_path, string_as_number);
    IF NOT (SELECT true = any (q_result.validation_booleans)) THEN
      RETURN q_result.all_errors || (schema_path, 'does not match any of the required schemas')::@extschema@.json_schema_validation_result;
    END IF;
  END IF;

  IF schema ? 'allOf' THEN
    q_result := @extschema@._validate_json_multiple_schemas(schema->'allOf', data, root_schema, schema_path, string_as_number);
    IF NOT (SELECT true = all(q_result.validation_booleans)) THEN
      RETURN q_result.all_errors || (schema_path, 'does not match all of the required schemas')::@extschema@.json_schema_validation_result;
    END IF;
  END IF;

  IF schema ? 'oneOf' THEN
    q_result := @extschema@._validate_json_multiple_schemas(schema->'oneOf', data, root_schema, schema_path, string_as_number);
    SELECT count(a::bool) INTO idx FROM unnest(q_result.validation_booleans) a WHERE a = true;
    IF (idx != 1) THEN
      RETURN ARRAY [(schema_path, format('should match exactly one of the schemas, but matches %s', idx))::@extschema@.json_schema_validation_result];
    END IF;
  END IF;

  IF COALESCE((schema->'uniqueItems')::text::boolean, false) THEN
    IF (SELECT COUNT(*) FROM jsonb_array_elements(data)) != (SELECT count(DISTINCT val) FROM jsonb_array_elements(data) val) THEN
      RETURN ARRAY [(schema_path, 'field has duplicates')];
    END IF;
  END IF;

  IF schema ? 'additionalProperties' AND jsonb_typeof(data) = 'object' THEN
    props := ARRAY(
      SELECT key
      FROM jsonb_object_keys(data) key
      WHERE key NOT IN (SELECT jsonb_object_keys(schema->'properties'))
        AND NOT EXISTS (SELECT * FROM jsonb_object_keys(schema->'patternProperties') pat WHERE key ~ pat)
    );
    IF jsonb_typeof(schema->'additionalProperties') = 'boolean' THEN
      IF NOT (schema->'additionalProperties')::text::boolean AND jsonb_typeof(data) = 'object' AND array_length(props, 1) > 0 THEN
        RETURN ARRAY [(schema_path, format('additionalProperties %s not allowed', props))];
      END IF;
    ELSE
      SELECT array_agg(q) INTO result FROM unnest(props) key, @extschema@.get_json_schema_validations(schema->'additionalProperties', data->key, root_schema, schema_path || key, string_as_number)  q1, unnest(q1) q;
      IF NOT (true = all(result::bool[])) THEN
        RETURN result;
      END IF;
    END IF;
  END IF;

  IF schema ? '$ref' THEN
    IF schema ? '$_resolvedRef' THEN
        path := ARRAY( SELECT jsonb_array_elements_text(schema->'$_resolvedRef') );
    ELSE
        -- ASSERT path[1] = '#', 'only refs anchored at the root are supported';
        path := @extschema@.json_schema_resolve_ref(schema->>'$ref', NULL, NULL, NULL);
    END IF;

    IF path IS NULL THEN
        RETURN ARRAY [(schema_path, format('$ref %s does not exist', schema->>'$ref'))];
    END IF;

    result := @extschema@.get_json_schema_validations(root_schema #> path, data, root_schema, schema_path, string_as_number);
    IF NOT (true = all(result::bool[])) THEN
      RETURN result;
    END IF;
  END IF;

  IF schema ? 'enum' THEN
    IF NOT EXISTS (SELECT * FROM jsonb_array_elements(schema->'enum') val WHERE val = data) THEN
      RETURN ARRAY [(schema_path, format('%s is an invalid enum value: %s', data, schema->'enum'))];
    END IF;
  END IF;

  IF schema ? 'const' THEN
      IF data != schema->'const' THEN
          RETURN ARRAY [(schema_path, format('value doe snot match const: %s', data, schema->'const'))];
      END IF;
  END IF;

  IF schema ? 'contains' AND jsonb_typeof(data) = 'array' THEN
    IF jsonb_array_length(data) < 1 THEN
        RETURN ARRAY [(schema_path, format('empty array does not have any items matching schema %s', schema->>'contains'))];
    END IF;
    SELECT array_agg(q::bool) AS a INTO q_result FROM jsonb_array_elements(data) WITH ORDINALITY t(elem, i),
        @extschema@.get_json_schema_validations(schema->'contains', elem, root_schema, schema_path || (i - 1)::text, string_as_number) q;
    IF false = ALL(q_result.a) THEN
        RETURN ARRAY [(schema_path, format('array does not contain any items matching schema %s', schema->>'contains'))];
    END IF;
  END IF;

  IF schema ? 'minLength' AND jsonb_typeof(data) = 'string' THEN
    IF char_length(data #>> '{}') < (schema->>'minLength')::numeric THEN
      RETURN ARRAY [(schema_path, format('field must be at least %s long', schema->>'minLength'))];
    END IF;
  END IF;

  IF schema ? 'maxLength' AND jsonb_typeof(data) = 'string' THEN
    IF char_length(data #>> '{}') > (schema->>'maxLength')::numeric THEN
      RETURN ARRAY [(schema_path, format('field may not be longer than %s', schema->>'maxLength'))];
    END IF;
  END IF;

  IF schema ? 'not' THEN
    result := @extschema@.get_json_schema_validations(schema->'not', data, root_schema, schema_path, string_as_number);
    IF (result) THEN
      RETURN ARRAY [(schema_path, format('field must not be any of %s', schema->'not'))];
    END IF;
  END IF;

  IF schema ? 'maxProperties' AND jsonb_typeof(data) = 'object' THEN
    SELECT count(*) INTO idx FROM jsonb_object_keys(data);
    IF idx > (schema->>'maxProperties')::numeric THEN
      RETURN ARRAY [(schema_path, format('field properties count %s exceeds maxProperties of %s', idx, schema->'maxProperties'))];
    END IF;
  END IF;

  IF schema ? 'minProperties' AND jsonb_typeof(data) = 'object' THEN
    SELECT count(*) INTO idx FROM jsonb_object_keys(data);
    IF idx < (schema->>'minProperties')::numeric THEN
      RETURN ARRAY [(schema_path, format('field properties count %s is less than minProperties of %s', idx, schema->'minProperties'))];
    END IF;
  END IF;

  IF schema ? 'maxItems' AND jsonb_typeof(data) = 'array' THEN
    SELECT count(*) INTO idx FROM jsonb_array_elements(data);
    IF idx > (schema->>'maxItems')::numeric THEN
      RETURN ARRAY [(schema_path, format('items count of %s exceeds maxItems of %s', idx, schema->'maxItems'))];
    END IF;
  END IF;

  IF schema ? 'minItems' AND jsonb_typeof(data) = 'array' THEN
    SELECT count(*) INTO idx FROM jsonb_array_elements(data);
    IF idx < (schema->>'minItems')::numeric THEN
      RETURN ARRAY [(schema_path, format('items count of %s is less than minItems of %s', idx, schema->'minItems'))];
    END IF;
  END IF;

  IF schema ? 'dependencies' AND jsonb_typeof(data) != 'array' THEN
    FOR prop IN SELECT jsonb_object_keys(schema->'dependencies') LOOP
      IF data ? prop THEN
        IF jsonb_typeof(schema->'dependencies'->prop) = 'array' THEN
          SELECT array_agg(dep) INTO props FROM jsonb_array_elements_text(schema->'dependencies'->prop) dep WHERE NOT data ? dep;
          IF (array_length(props, 1) > 0) THEN
            RETURN ARRAY [(schema_path || prop, format('missing required dependencies %s', props))];
          END IF;
        ELSE
          result := @extschema@.get_json_schema_validations(schema->'dependencies'->prop, data, root_schema, schema_path, string_as_number);
          IF NOT result THEN
            RETURN result;
          END IF;
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF schema ? 'pattern' AND jsonb_typeof(data) = 'string' THEN
    IF (data #>> '{}') !~ (schema->>'pattern') THEN
      RETURN ARRAY [(schema_path, format('field does not match pattern %s', schema->>'pattern'))];
    END IF;
  END IF;

  IF schema ? 'patternProperties' AND jsonb_typeof(data) = 'object' THEN
    FOR prop IN SELECT jsonb_object_keys(data) LOOP
      FOR pattern IN SELECT jsonb_object_keys(schema->'patternProperties') LOOP
        IF prop ~ pattern AND NOT @extschema@.get_json_schema_validations(schema->'patternProperties'->pattern, data->prop, root_schema, schema_path, string_as_number) THEN
          RETURN ARRAY [(schema_path || prop, format('field does not match pattern %s', pattern))];
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  IF schema ? 'multipleOf' AND jsonb_typeof(data) = 'number' THEN
    IF data::text::numeric % (schema->>'multipleOf')::numeric != 0 THEN
      RETURN ARRAY [(schema_path, format('value must be a multiple of %s', schema->>'multipleOf'))];
    END IF;
  END IF;


  IF schema ? 'propertyNames' AND jsonb_typeof(data) = 'object' THEN
    result := ARRAY( SELECT v FROM jsonb_object_keys(data) propName, @extschema@.get_json_schema_validations(schema->'propertyNames', to_jsonb(propName), root_schema, schema_path || propName, string_as_number) v WHERE not v);
    IF NOT result THEN
        RETURN result;
    END IF;
  END IF;


  IF schema ? 'if' AND (schema ? 'then' OR schema ? 'else') THEN
    result := @extschema@.get_json_schema_validations(schema->'if', data, root_schema, schema_path || 'if'::text, string_as_number);
    IF result AND schema ? 'then' THEN
      result := @extschema@.get_json_schema_validations(schema->'then', data, root_schema, schema_path || 'then'::text, string_as_number);
    ELSEIF NOT result AND schema ? 'else' THEN
      result := @extschema@.get_json_schema_validations(schema->'else', data, root_schema, schema_path || 'else'::text, string_as_number);
    ELSE
      result := NULL;
    END IF;

    IF NOT result THEN
      RETURN result;
    END IF;
  END IF;

  RETURN '{}'::@extschema@.json_schema_validation_result[];
END;
$f$ LANGUAGE 'plpgsql' VOLATILE ;


CREATE OR REPLACE FUNCTION json_schema_resolve_uri(
    to_resolve text,
    OUT resolved_uri text,
    IN OUT base_uri text default null,
    IN OUT base_path text default null
    )
RETURNS RECORD AS $f$
    DECLARE
        v_parts text[];
        v_path text;
    BEGIN
        IF to_resolve LIKE 'urn:%' THEN

            IF to_resolve LIKE '%#%' THEN
                v_parts = string_to_array(to_resolve, '#');
                base_uri := v_parts[1];
                base_path := '';
                resolved_uri := base_uri || '#' || v_parts[2];
            ELSE
                base_uri := to_resolve;
                base_path := '';
                resolved_uri := to_resolve;
            END IF;
            RETURN;

        ELSEIF to_resolve LIKE '%://%' THEN
            v_parts := string_to_array(to_resolve, '/');
            IF base_uri IS NULL THEN
                base_uri := v_parts[1] || '//' || v_parts[3];
            END IF;
            v_path := '/' || array_to_string(v_parts[4:], '/');
        ELSE
            v_path := to_resolve;
        END IF;

        IF v_path LIKE '/%' THEN
            base_path := v_path;
        ELSE
            IF v_path LIKE '#%' OR base_path LIKE '%/' THEN
                base_path := coalesce(base_path, '') || v_path;
            ELSEIF base_path IS NOT NULL THEN
                v_parts := string_to_array(base_path, '/');
                base_path := array_to_string( v_parts[ 1 : array_length(v_parts, 1) - 1], '/' ) || '/' || v_path;
            ELSE
                base_path := '/' || v_path;
            END IF;
        END IF;
        resolved_uri := coalesce(base_uri, '') || base_path;
    END;
$f$ LANGUAGE plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION json_schema_resolve_refs(
    IN OUT schema jsonb,
    base_uri text,
    base_path text,
    resolved_ids_mapping jsonb,
    resolve_refs bool
) AS $f$
    DECLARE
        id text;
        sub_schema jsonb;
        resolved_path text[];
        resolved_uri text;
        key text;
        idx int;
    BEGIN
        IF resolve_refs THEN
            IF schema ? '$ref' THEN
                resolved_path := (@extschema@.json_schema_resolve_ref(schema->>'$ref', base_uri, base_path, resolved_ids_mapping));
                schema := jsonb_set(schema, ARRAY['$_resolvedRef'], to_jsonb(resolved_path));
            END IF;

            IF schema ? 'id' THEN
                id := schema->>'id';
            ELSEIF schema ? '$id' THEN
                id := schema->>'$id';
            END IF;
            IF id IS NOT NULL THEN
                 SELECT t.resolved_uri, t.base_uri, t.base_path
                 INTO resolved_uri, base_uri, base_path
                 FROM @extschema@.json_schema_resolve_uri(id, base_uri, base_path) t;
            END IF;
        END IF;

        IF jsonb_typeof(schema) = 'object' THEN
            FOR key, sub_schema IN SELECT t.key, schema->(t.key) FROM jsonb_object_keys(schema) t(key) WHERE t.key NOT IN ('enum', 'const') LOOP
                SELECT t.schema INTO sub_schema
                    FROM @extschema@.json_schema_resolve_refs(
                        sub_schema,
                        base_uri,
                        base_path,
                        resolved_ids_mapping,
                        NOT resolve_refs OR (resolve_refs AND key NOT IN ('properties'))
                        ) t;
                schema := jsonb_set(schema, ARRAY [key], sub_schema);
            END LOOP;

        ELSEIF jsonb_typeof(schema) = 'array' THEN
            FOR idx IN 0..jsonb_array_length(schema) - 1 LOOP
                SELECT t.schema INTO sub_schema
                   FROM @extschema@.json_schema_resolve_refs(schema->idx,  base_uri, base_path, resolved_ids_mapping, resolve_refs) t;
                schema := jsonb_set(schema, ARRAY [idx::text], sub_schema);
            END LOOP;
        END IF;
    END;
$f$ LANGUAGE plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION json_schema_resolve_ref(
    ref text,
    base_uri text,
    base_path text,
    resolved_ids_mapping jsonb
) RETURNS text[]
    AS $f$
    DECLARE
        v_parts text[];
        v_frag text := '';
        v_uri text := '';
        v_path jsonb;
    BEGIN
        -- a ref could be to a $id or a json property path.
        v_parts := string_to_array(ref, '#');
        IF array_length(v_parts, 1) < 2 THEN
            -- we only have one part
            v_uri = v_parts[1];
        ELSE
            v_uri = v_parts[1];
            v_frag = v_parts[2];
        END IF;

        IF v_frag != '' THEN
            v_parts := ARRAY(
                SELECT @extschema@.urldecode_arr(replace(replace(path_part, '~1', '/'), '~0', '~'))
                FROM UNNEST(string_to_array(v_frag, '/')) path_part
                );
            IF v_uri LIKE 'urn:%' AND v_frag LIKE '/%' THEN
                -- urn:something:there#/frag/part
                -- /frag/json/pointer/part
                v_parts := v_parts[2:];
            ELSEIF v_uri != '' AND array_length(v_parts, 1) > 0 THEN
                -- http://example.com/path#foo.json
                v_uri := v_uri || '#' || v_parts[1];
                -- /frag/json/pointer/part
                v_parts := v_parts[2:];
            ELSEIF v_parts[1] = '' THEN
                -- #/frag/json/pointer/part without the first item which is empty
                v_parts := v_parts[2:];
            END IF;
        ELSE
            v_parts := '{}'::text[];
        END IF;

        IF v_uri != '' THEN
            v_uri := (@extschema@.json_schema_resolve_uri(v_uri, base_uri, base_path)).resolved_uri;
            IF resolved_ids_mapping IS NULL THEN
                RETURN NULL;
            END IF;
            IF NOT resolved_ids_mapping ? v_uri THEN
                RETURN NULL;
            END IF;
            RETURN ARRAY(SELECT jsonb_array_elements_text(resolved_ids_mapping->v_uri)) || v_parts;
        ELSEIF v_frag = '' THEN
            RETURN ARRAY[]::text[];
        ELSEIF resolved_ids_mapping ? (base_uri || base_path) THEN
            v_path := resolved_ids_mapping->(base_uri || base_path);
            RETURN ARRAY(SELECT jsonb_array_elements_text(v_path)) || v_parts;
        ELSEIF (ref ~ '^#.[^/]+$') AND resolved_ids_mapping ? ref THEN
            RETURN ARRAY(SELECT jsonb_array_elements_text(resolved_ids_mapping->ref));
        ELSE
            RETURN v_parts;
        END IF;
    END;
$f$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION json_schema_resolve_ids_to_paths (
    schema jsonb,
    path text[],
    base_uri text,
    base_path text
) RETURNS TABLE (
        resolved_uri text,
        resolved_path text[]
    ) AS $f$
    DECLARE
        id text;
        V_resolved_uri ALIAS FOR resolved_uri;
    BEGIN
        IF schema ? 'id' THEN
            id := schema->>'id';
        ELSEIF schema ? '$id' THEN
            id := schema->>'$id';
        END IF;
        IF id IS NOT NULL THEN
             SELECT t.resolved_uri, t.base_uri, t.base_path
             INTO V_resolved_uri, base_uri, base_path
             FROM @extschema@.json_schema_resolve_uri(id, base_uri, base_path) t;
        END IF;

        IF jsonb_typeof(schema) = 'object' THEN
            RETURN QUERY SELECT q.*
                         FROM jsonb_object_keys(schema) t(key),
                              @extschema@.json_schema_resolve_ids_to_paths(schema->(t.key), path || t.key, base_uri, base_path) q;


        ELSEIF jsonb_typeof(schema) = 'array' THEN
            RETURN QUERY SELECT q.*
                         FROM jsonb_array_elements(schema) WITH ORDINALITY t(elem, idx),
                              @extschema@.json_schema_resolve_ids_to_paths(elem, path || (idx - 1)::text, base_uri, base_path) q;

        END IF;
        resolved_path := path;
        RETURN NEXT;
    END;
$f$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION json_schema_resolve_ids_to_paths(schema jsonb) RETURNS TABLE (
        resolved_uri text,
        resolved_path text[]
    ) AS $$
    SELECT * FROM @extschema@.json_schema_resolve_ids_to_paths(schema, '{}'::text[], null, null) t
    WHERE t.resolved_uri IS NOT NULL;
$$ LANGUAGE SQL IMMUTABLE ;

CREATE OR REPLACE FUNCTION json_schema_resolve_refs(schema jsonb) RETURNS jsonb AS $$
    SELECT schema FROM @extschema@.json_schema_resolve_refs(
        schema,
        null,
        null,
        (SELECT jsonb_object_agg(resolved_uri, resolved_path) FROM @extschema@.json_schema_resolve_ids_to_paths(schema)),
        true
        );
$$ LANGUAGE SQL IMMUTABLE ;
