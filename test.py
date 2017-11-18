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
    ('ref.json', 'escaped pointer ref', 'percent invalid'),

    # json-schema-org/JSON-Schema-Test-Suite#114
    ('ref.json', 'remote ref, containing refs itself', 'remote ref invalid'),
}

os.chdir('JSON-Schema-Test-Suite/tests/draft4')
failures = 0

test_files = sys.argv[1:]
if not test_files:
    test_files = [test_file for test_file in os.listdir('.') if test_file not in EXCLUDE_FILES]

for test_file in test_files:
    with open(test_file) as f:
        suites = json.load(f)
        for suite in suites:
            for test in suite['tests']:
                if (test_file, suite['description'], test['description']) in EXCLUDE_TESTS:
                    continue

                def fail(e):
                    print("%s: validate_json_schema('%s', '%s')" % (test_file, json.dumps(suite['schema']), json.dumps(test['data'])))
                    print('Failed: %s: %s. %s' % (suite['description'], test['description'], e))
                try:
                    cur.execute('SELECT validate_json_schema(%s, %s)', (json.dumps(suite['schema']), json.dumps(test['data'])))
                except psycopg2.DataError as e:
                    fail(e)
                    failures += 1
                else:
                    valid, = cur.fetchone()
                    if valid != test['valid']:
                        fail(valid)
                        failures += 1

sys.exit(failures)
