"""Offline integration tests: python3 -m unittest discover -s tests -v."""
import datetime
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]


class WeeklyImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.env = dict(os.environ, DB_FILE=str(self.path / 'matches.db'),
                        LOG_FILE=str(self.path / 'etl.log'), MOCK_DIR=str(self.path))
        self.env['PATH'] = str(self.path) + os.pathsep + self.env['PATH']
        self.write_command('curl', '''#!/usr/bin/env python3
import os, sys
from pathlib import Path
p = Path(os.environ['MOCK_DIR'])
with (p / 'requests').open('a') as log:
    log.write(sys.argv[-1] + '\\n')
codes = (p / 'codes').read_text().split()
code = codes.pop(0) if codes else '200'
(p / 'codes').write_text(' '.join(codes))
body = (p / 'response').read_text() if 'matches?' in sys.argv[-1] else '{"name":"Premier League"}'
Path(sys.argv[sys.argv.index('-o') + 1]).write_text(body)
print(code, end='')
sys.exit(7 if code == '000' else 0)
''')
        self.write_command('sleep', '#!/bin/sh\nexit 0\n')
        (self.path / 'codes').write_text('')
        self.match = {
            'id': 123, 'season': {'id': 9999, 'startDate': '2026-08-01'},
            'matchday': 7, 'utcDate': '2026-10-05T19:00:00Z',
            'homeTeam': {'id': 1, 'name': 'Home'},
            'awayTeam': {'id': 2, 'name': 'Away'}, 'referees': [],
            'status': 'FINISHED', 'score': {'fullTime': {'home': 2, 'away': 1}},
        }

    def write_command(self, name, content):
        target = self.path / name
        target.write_text(content)
        target.chmod(0o755)

    def run_import(self, matches=None, raw=None):
        (self.path / 'response').write_text(
            raw if raw is not None else json.dumps({'matches': matches or []}))
        return subprocess.run(['bash', str(ROOT / 'weekly.sh')], cwd=self.path,
                              env=self.env, text=True, capture_output=True, timeout=15)

    def test_range_and_repeated_import_refresh_scores(self):
        result = self.run_import([self.match])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        today = datetime.datetime.now(ZoneInfo('Europe/London')).date()
        start = today - datetime.timedelta(days=7)
        self.assertIn(f'dateFrom={start}&dateTo={today}', (self.path / 'requests').read_text())
        self.match['score']['fullTime']['home'] = 3
        result = self.run_import([self.match])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with sqlite3.connect(self.env['DB_FILE']) as db:
            self.assertEqual(db.execute('SELECT season_id, home_score, away_score FROM matches').fetchall(),
                             [(2026, 3, 1)])
            self.assertEqual(db.execute('SELECT COUNT(*) FROM teams').fetchone(), (2,))

    def test_empty_week_succeeds(self):
        self.assertEqual(self.run_import().returncode, 0)

    def test_invalid_response_fails(self):
        self.assertNotEqual(self.run_import(raw='{"error":"bad payload"}').returncode, 0)

    def test_rate_limit_recovery_preserves_json(self):
        (self.path / 'codes').write_text('200 429 200')
        result = self.run_import([self.match])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rate_limits_and_network_errors_are_bounded(self):
        for code in ('429', '000', '500'):
            with self.subTest(code=code):
                (self.path / 'codes').write_text(f'{code} {code} {code}')
                (self.path / 'requests').write_text('')
                result = self.run_import()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len((self.path / 'requests').read_text().splitlines()), 3)

    def test_database_failure_is_reported(self):
        self.env['DB_FILE'] = str(self.path / 'missing' / 'matches.db')
        self.assertNotEqual(self.run_import().returncode, 0)

    def test_overlapping_run_skips_api(self):
        import fcntl
        with open(self.env['DB_FILE'] + '.weekly.lock', 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.path / 'requests').exists())
