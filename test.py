import os
import json
import sys

import psycopg2


conn = psycopg2.connect(os.environ['DATABASE_URL'])
conn.set_session(autocommit=True)

cur = conn.cursor()

EXCLUDE_FILES = {'optional', 'refRemote.json', 'definitions.json'}
EXCLUDE_TESTS = {
    # json-schema-org/JSON-Schema-Test-Suite#130
#    ('ref.json', 'escaped pointer ref', 'percent invalid'),

    # json-schema-org/JSON-Schema-Test-Suite#114
    ('ref.json', 'remote ref, containing refs itself'),
#    ('id.json', 'id inside an enum is not a real identifier'),

    # nul bytes are not supported by postgres
    ('enum.json', 'nul characters in strings'),
    ('const.json', 'nul characters in strings'),

    # we are implementing like draft 2019 so we do include sibling props
    ('ref.json', 'ref overrides any sibling keywords'),
}

if '--dir' in sys.argv:
    idx = sys.argv.index('--dir')
    dir_name = sys.argv[idx+1]
    test_files = sys.argv[1:idx] + sys.argv[idx+2:]
else:
    dir_name = 'JSON-Schema-Test-Suite/tests/draft4'
    test_files = sys.argv[1:]

print(f'switching to {dir_name} {sys.argv}')
#os.chdir(dir_name)
failures = 0

if not test_files:
    test_files = [os.path.join(dir_name, test_file) for test_file in os.listdir(dir_name) if test_file not in EXCLUDE_FILES]

for test_file in test_files:
    with open(test_file) as f:
        test_file = os.path.basename(test_file)
        suites = json.load(f)
        for suite in suites:
            for test in suite['tests']:
                if (test_file, suite['description']) in EXCLUDE_TESTS:
                    continue
                if (test_file, suite['description'], test['description']) in EXCLUDE_TESTS:
                    continue

                command_args = ['SELECT validate_json_schema(json_schema_resolve_refs(%s), %s)', (json.dumps(suite['schema']), json.dumps(test['data']))]

                def fail(e):
                    cmd = command_args[0] % tuple("'%s'" % x for x in command_args[1])
                    print("%s: %s" % (test_file, cmd))
                    print('Failed: %s: %s. %s' % (suite['description'], test['description'], e))
                try:
                    cur.execute(command_args[0], command_args[1])
                except psycopg2.DataError as e:
                    fail(e)
                    failures += 1
                except psycopg2.errors.StatementTooComplex as e:
                    fail(e)
                    exit(1)
                else:
                    valid, = cur.fetchone()
                    if valid != test['valid']:
                        fail(valid)
                        failures += 1

sys.exit(failures)
