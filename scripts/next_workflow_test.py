# Copyright (c) 2026 Lark Technologies Pte. Ltd.
# SPDX-License-Identifier: MIT

"""Contract checks for the additional offline gate (stdlib only)."""
import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OfflineWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/next-offline.yml').read_text()
        self.makefile = (ROOT / 'Makefile').read_text()

    def test_correctness_workflows_run_on_pull_requests(self):
        for name in ('ci', 'next-offline'):
            workflow = (ROOT / f'.github/workflows/{name}.yml').read_text()
            triggers = workflow.split('on:\n', 1)[1].split('\n\n', 1)[0]
            self.assertIn('  pull_request:\n', triggers)
            self.assertIn('  push:\n    branches: [main]', triggers)
            self.assertNotIn('pull_request_target:', triggers)

    def test_linux_job_keeps_every_gate_required(self):
        self.assertIn('runs-on: [self-hosted, linux, x64, feishu-ci]', self.workflow)
        self.assertNotIn('matrix', self.workflow)
        self.assertNotIn('macos-latest', self.workflow)
        self.assertNotIn('windows-latest', self.workflow)
        self.assertNotIn('continue-on-error', self.workflow)
        self.assertNotIn('exclude:', self.workflow)
        for selector in ('--section all --suite all', '--integration sheets_base',
                         '--harness scripts', '--harness evaluation'):
            self.assertIn('python scripts/next_test.py ' + selector, self.workflow)
        self.assertNotIn('--allow-live', self.workflow)
        self.assertNotIn('secrets.', self.workflow)
        self.assertNotIn('pull_request_target:', self.workflow)
        self.assertIn('contents: read', self.workflow)
        self.assertIn('persist-credentials: false', self.workflow)
        for action in re.findall(r'uses: (\S+)', self.workflow):
            self.assertRegex(action, r'@\w{40}$')

    def test_dependencies_preload_before_isolated_suites_and_reports_always_upload(self):
        self.assertLess(self.workflow.index('go mod download'), self.workflow.index('python scripts/next_test.py'))
        self.assertIn("('GOCACHE', 'GOMODCACHE')", self.workflow)
        self.assertNotIn('scripts/next_meta.py', self.workflow)
        self.assertIn('Build with committed API catalog', self.workflow)
        for stage in ('scripts', 'sections', 'evaluation', 'integration'):
            self.assertIn('--report .tmp/next-ci/' + stage + '.json', self.workflow)
            self.assertIn('steps.' + stage + '.outcome', self.workflow)
        self.assertRegex(self.workflow, r'(?s)name: Record gate outcomes.*?if: \$\{\{ always\(\) \}\}')
        self.assertRegex(self.workflow, r'(?s)name: Upload all machine-readable evidence\n\s+if: \$\{\{ always\(\) \}\}')
        self.assertIn('if-no-files-found: error', self.workflow)
        self.assertIn("'evidence': 'offline'", self.workflow)
        self.assertIn('Skipped or blocked scenarios remain unverified', self.workflow)

    def test_job_uses_linux_binary(self):
        job_env = self.workflow.split('    env:\n', 1)[1].split('    steps:\n', 1)[0]
        self.assertNotIn('runner.', job_env)
        self.assertIn("NEXT_BINARY: feishu-cli-next", job_env)

    def test_local_go_caches_do_not_round_trip_through_actions_cache(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            if path.name == 'release.yml':
                continue
            for step in re.split(r'\n\s+- uses:', path.read_text())[1:]:
                if step.lstrip().startswith('actions/setup-go@'):
                    self.assertIn('cache: false', step, str(path))

    def test_capability_guard_executes_actual_helper_as_required_stage(self):
        stage = self.workflow.split('      - name: Compare configured-brand capability registrations\n', 1)[1].split('      - name:', 1)[0]
        self.assertIn('id: capabilities', stage)
        self.assertIn("if: ${{ always() && steps.dependencies.outcome == 'success' && steps.build.outcome == 'success' }}", stage)
        self.assertIn('run: python scripts/next_inventory.py gate --target . --reference-dir docs/reference/v1.0.97 --mapping docs/reference/v1.0.97/next-interface-mapping.json.gz --out .tmp/next-ci/capabilities.json\n', stage)
        self.assertNotIn('continue-on-error', stage)
        self.assertNotIn('||', stage)
        self.assertLess(self.workflow.index('go build -trimpath'), self.workflow.index('id: capabilities'))
        self.assertIn('CAPABILITIES_OUTCOME: ${{ steps.capabilities.outcome }}', self.workflow)
        self.assertIn('path: .tmp/next-ci/', self.workflow)
        self.assertIn('Capability reconciliation does not clear retained source review_required findings.', self.workflow)

    def test_always_gate_report_preserves_failed_capability_stage(self):
        stage = self.workflow.split('      - name: Record gate outcomes and evidence limits\n', 1)[1].split('      - name:', 1)[0]
        source = textwrap.dedent(re.search(r"python - <<'PY'\n(.*?)\n          PY", stage, re.DOTALL).group(1))
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, GITHUB_SHA='synthetic-revision', CAPABILITIES_OUTCOME='failure')
            result = subprocess.run([sys.executable, '-c', source], cwd=directory, env=env,
                                    capture_output=True, encoding='utf-8', timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((Path(directory) / '.tmp/next-ci/gate.json').read_text(encoding='utf-8'))
        self.assertEqual(report['stages']['capabilities'], 'failure')
        self.assertEqual(report['stages']['integration'], 'not_run')
        self.assertEqual(report['evidence'], 'offline')
        self.assertNotIn('pass', report.values())

    def test_make_keeps_original_gates_and_includes_cross_domain_and_python(self):
        self.assertIn('cross-domain-test: build\n', self.makefile)
        self.assertIn('integration-test: build cross-domain-test\n', self.makefile)
        self.assertIn('script-test: next-script-test\n', self.makefile)
        self.assertIn('test: vet fmt-check script-test unit-test examples-build integration-test evaluation-test', self.makefile)
        self.assertIn('bash scripts/ci-workflow.test.sh', self.makefile)
        script_target = self.makefile.split('script-test: next-script-test\n', 1)[1].split('\n\n', 1)[0]
        self.assertIn('\tbash scripts/check-doc-tokens.sh\n', script_target)
        self.assertIn('--harness scripts', self.makefile)
        self.assertIn('--harness evaluation', self.makefile)
        self.assertIn('--integration sheets_base', self.makefile)


if __name__ == '__main__':
    unittest.main()
