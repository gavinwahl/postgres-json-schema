CREATE OR REPLACE FUNCTION run_tests() RETURNS boolean AS $f$
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


  RETURN true;
END;
$f$ LANGUAGE 'plpgsql';

SELECT run_tests();
