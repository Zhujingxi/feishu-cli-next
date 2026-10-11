#!/usr/bin/env bash
# Copyright (c) 2026 Lark Technologies Pte. Ltd.
# SPDX-License-Identifier: MIT

set -euo pipefail

workflow=".github/workflows/ci.yml"
job_section() {
  local job="$1"
  awk -v job="$job" '
    $0 == "  " job ":" { in_job = 1; print; next }
    in_job && /^  [A-Za-z0-9_-]+:/ { exit }
    in_job { print }
  ' "$workflow"
}
workflow_permissions="$(awk '
  /^permissions:/ { in_permissions = 1; print; next }
  in_permissions && /^[^[:space:]]/ { exit }
  in_permissions { print }
' "$workflow")"
workflow_concurrency="$(awk '
  /^concurrency:/ { in_concurrency = 1; print; next }
  in_concurrency && /^[^[:space:]]/ { exit }
  in_concurrency { print }
' "$workflow")"
fast_gate_section="$(job_section fast-gate)"
unit_test_section="$(job_section unit-test)"
lint_section="$(awk '
  /^  lint:/ { in_job = 1 }
  in_job { print }
  /^  script-test:/ { exit }
' "$workflow")"
script_test_section="$(job_section script-test)"
deterministic_section="$(awk '
  /^  deterministic-gate:/ { in_job = 1 }
  in_job { print }
  /^  coverage:/ { exit }
' "$workflow")"
coverage_job_section="$(job_section coverage)"
deadcode_section="$(job_section deadcode)"
dry_run_section="$(job_section e2e-dry-run)"
security_section="$(job_section security)"
license_header_section="$(job_section license-header)"
results_section="$(awk '
  /^  results:/ { in_job = 1 }
  in_job { print }
' "$workflow")"
fork_safe_guard="github.event_name != 'pull_request' || !github.event.pull_request.head.repo.fork"

if ! grep -Fq 'LARK_CLI_BIN: ${{ github.workspace }}/feishu-cli-next' <<<"$dry_run_section"; then
  echo "CLI E2E must use the feishu-cli-next binary produced by make build" >&2
  exit 1
fi

if ! grep -Fq "run-name: \${{ github.event_name == 'pull_request' && format('CI / {0}', github.event.pull_request.number) || '' }}" "$workflow"; then
  echo "CI should expose a stable PR generation while preserving default push and manual run titles" >&2
  exit 1
fi

if ! grep -Fq 'group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}' <<<"$workflow_concurrency"; then
  echo "CI should deduplicate runs for the same pull request without grouping push or manual runs" >&2
  exit 1
fi

if ! grep -Fq "cancel-in-progress: \${{ github.event_name == 'pull_request' }}" <<<"$workflow_concurrency"; then
  echo "CI should cancel superseded pull request runs but preserve push and manual runs" >&2
  exit 1
fi

for denied_permission in "checks: write" "pull-requests: write" "issues: write"; do
  if grep -Eq "^[[:space:]]*${denied_permission}$" <<<"$workflow_permissions"; then
    echo "CI workflow must not grant ${denied_permission} at the workflow level" >&2
    exit 1
  fi
done

if ! grep -Fq "contents: read" <<<"$workflow_permissions" || ! grep -Fq "actions: read" <<<"$workflow_permissions"; then
  echo "CI workflow should keep only read permissions at the workflow level"
  exit 1
fi

if ! grep -Fq "deterministic-gate:" <<<"$deterministic_section"; then
  echo "CI should expose deterministic-gate as a standalone job"
  exit 1
fi

if grep -Fq "make quality-gate" <<<"$lint_section"; then
  echo "lint job should not run deterministic quality gate"
  exit 1
fi

if ! grep -Fq "needs: fast-gate" <<<"$deterministic_section"; then
  echo "deterministic-gate should depend on fast-gate"
  exit 1
fi

if ! grep -Fq "permissions:" <<<"$deterministic_section"; then
  echo "deterministic-gate should define job-level permissions"
  exit 1
fi

if ! grep -Fq "contents: read" <<<"$deterministic_section"; then
  echo "deterministic-gate should only need read access to repository contents"
  exit 1
fi

if ! grep -Fq "actions: read" <<<"$deterministic_section"; then
  echo "deterministic-gate should keep actions access read-only"
  exit 1
fi

if grep -Fq "checks: write" <<<"$deterministic_section"; then
  echo "deterministic-gate should not inherit check write permission"
  exit 1
fi

if grep -Fq "pull-requests: write" <<<"$deterministic_section"; then
  echo "deterministic-gate should not inherit pull request write permission"
  exit 1
fi

if grep -Fq '${{ secrets.' <<<"$deterministic_section"; then
  echo "deterministic-gate must not reference secrets"
  exit 1
fi

if ! grep -Fq "Run CLI deterministic gate" <<<"$deterministic_section"; then
  echo "deterministic-gate should run the CLI deterministic gate step"
  exit 1
fi

if ! grep -Fq "make quality-gate" <<<"$deterministic_section"; then
  echo "deterministic-gate should invoke make quality-gate"
  exit 1
fi

if ! grep -Fq "Write public content metadata" <<<"$deterministic_section"; then
  echo "deterministic-gate should write PR title/body metadata before quality-gate"
  exit 1
fi

ruby -ropen3 -rtempfile -ryaml <<'RUBY'
ci = YAML.load_file(".github/workflows/ci.yml")
FEISHU_AUTH_KEY = /(?:TEST_(?:BOT\d+_APP_(?:ID|SECRET)|TENANT_ACCESS_TOKEN|USER_ACCESS_TOKEN)|LARKSUITE_CLI_(?:APP_ID|APP_SECRET|TENANT_ACCESS_TOKEN|USER_ACCESS_TOKEN))/
def check_offline_feishu_workflow(value, file)
  case value
  when Hash
    value.fetch("env", {}).each do |name, configured|
      next unless name.match?(/\A#{FEISHU_AUTH_KEY}\z/)
      allowed = name.start_with?("LARKSUITE_CLI_APP_") ? [nil, "", "dry-run"] : [nil, ""]
      raise ArgumentError, "#{file}: #{name} must not enable real Feishu authentication in CI" unless allowed.include?(configured)
    end
    value.each_value { |item| check_offline_feishu_workflow(item, file) }
  when Array
    value.each { |item| check_offline_feishu_workflow(item, file) }
  when String
    if value.match?(/(?:secrets|vars)\s*(?:\.\s*(?:TEST_|FEISHU_|LARKSUITE_CLI_)|\[\s*['"](?:TEST_|FEISHU_|LARKSUITE_CLI_))|fetch_e2e_tat|--allow-live|--suite[= ]+live|needs\.e2e-live/)
      raise ArgumentError, "#{file}: workflows must not require real Feishu credentials or live API tests"
    end
    if value.match?(/(?:\A|[;\n])\s*(?:(?:export|env)\s+|echo\s+["']?)?#{FEISHU_AUTH_KEY}\s*=[^\n]*\$\{\{\s*(?:secrets|vars)\s*[.\[]/)
      raise ArgumentError, "#{file}: shell assignments must not inject real Feishu authentication in CI"
    end
  end
end
# Exercise isolated workflow values so placeholder and unrelated secrets stay valid.
[
  [{ "env" => { "LARKSUITE_CLI_APP_SECRET" => "dry-run" } }, true],
  [{ "run" => 'LARKSUITE_CLI_APP_SECRET=dry-run go test ./...' }, true],
  [{ "env" => { "ARK_API_KEY" => '${{ secrets.ARK_API_KEY }}' } }, true],
  [{ "run" => 'if name == "LARKSUITE_CLI_APP_SECRET=${{ secrets.UNRELATED }}"; then exit 1; fi' }, true],
  [{ "env" => { "LARKSUITE_CLI_APP_SECRET" => '${{ secrets.UNRELATED }}' } }, false],
  [{ "run" => 'LARKSUITE_CLI_APP_SECRET="${{ secrets.UNRELATED }}" go test ./...' }, false],
  [{ "run" => 'export TEST_USER_ACCESS_TOKEN=${{ vars.UNRELATED }}' }, false],
  [{ "run" => 'echo "LARKSUITE_CLI_APP_SECRET=${{ secrets["UNRELATED"] }}" >> "$GITHUB_ENV"' }, false],
].each do |fixture, expected|
  accepted = begin
    check_offline_feishu_workflow(fixture, "fixture.yml")
    true
  rescue ArgumentError
    false
  end
  abort("Feishu-auth workflow guard regression: #{fixture.inspect}") unless accepted == expected
end
Dir.glob(".github/workflows/*.{yml,yaml}").each do |file|
  config = YAML.load_file(file)
  # The paused release pipeline retains native macOS signing/verification.
  # Every other checked-in workflow belongs to the repository-scoped runner.
  unless File.basename(file) == "release.yml"
    config.fetch("jobs").each do |name, job|
      unless job["runs-on"] == ["self-hosted", "linux", "x64", "feishu-ci"]
        abort("#{file}: #{name} must use the repository-scoped Linux CI runner")
      end
    end
  end
  abort("#{file}: CI must not contain a live Feishu E2E job") if config.fetch("jobs").key?("e2e-live")
  begin
    check_offline_feishu_workflow(config, file)
  rescue ArgumentError => error
    abort(error.message)
  end
end
results = ci.dig("jobs", "results")
unless results.fetch("needs").include?("e2e-dry-run") &&
       results.fetch("steps").any? { |step| step.fetch("run", "").include?("needs.e2e-dry-run.result") }
  abort("dry-run E2E must remain a required result")
end
# Run the actual threshold step with cover output containing misleading names.
coverage_check = ci.dig("jobs", "coverage", "steps").find { |step| step["name"] == "Check coverage threshold" }.fetch("run")
Dir.mktmpdir("ci-coverage") do |directory|
  go = File.join(directory, "go")
  File.write(go, "#!/bin/bash\nprintf '%s\\n' \"$COVER_OUTPUT\"\n")
  File.chmod(0755, go)
  [
    ["83.4%", true], ["40.0%", true], ["39.9%", false], ["invalid", false], [nil, false],
  ].each do |percent, expected|
    output = "example/total.go:10:\ttotalCount\t0.0%\n"
    output += "total: (statements) #{percent}\n" if percent
    _stdout, stderr, status = Open3.capture3(
      { "PATH" => "#{directory}:#{ENV.fetch('PATH')}", "COVER_OUTPUT" => output },
      "bash", "-e", "-o", "pipefail", "-c", coverage_check)
    abort("coverage threshold regression for #{percent.inspect}: #{stderr}") unless status.success? == expected
  end
end
security = ci.dig("jobs", "security")
scan = security.fetch("steps").find { |step| step["name"] == "govulncheck" }
abort("security job must run for every CI event and block failures") if security["if"] || security["continue-on-error"]
unless scan && !scan["continue-on-error"] && !scan["if"] &&
       scan["run"] == "go run golang.org/x/vuln/cmd/govulncheck@v1.9.0 ./..."
  abort("govulncheck must run directly and fail CI on vulnerabilities")
end
abort("security must remain a required result") unless results.fetch("needs").include?("security")
%w[success failure cancelled].each do |security_result|
  run = results.fetch("steps").find { |step| step["name"] == "Evaluate results" }.fetch("run")
  run = run.gsub(/\$\{\{ needs\.([\w-]+)\.result \}\}/) { Regexp.last_match(1) == "security" ? security_result : "success" }
  Tempfile.create("ci-security-summary") do |summary|
    _stdout, stderr, status = Open3.capture3({ "GITHUB_STEP_SUMMARY" => summary.path }, "bash", "-e", "-c", run)
    unless status.success? == (security_result == "success")
      abort("results must propagate security #{security_result}: #{stderr}")
    end
  end
end
%w[ci next-offline skill-format-check pr-labels-test pkg-pr-new].each do |name|
  config = YAML.load_file(".github/workflows/#{name}.yml")
  triggers = config.fetch("on") { config.fetch(true) }
  expected = case name
             when "ci", "next-offline" then %w[pull_request push workflow_dispatch]
             when "pkg-pr-new" then %w[workflow_dispatch]
             else %w[push workflow_dispatch]
             end
  abort("#{name} must use only #{expected.join(', ')} triggers") unless triggers.keys.sort == expected
  if name == "ci"
    abort("CI must rerun metadata gates after PR edits") unless triggers.dig("pull_request", "types") == %w[opened synchronize reopened edited]
  end
  if expected.include?("push")
    abort("#{name} must retain main push runs") unless triggers.dig("push", "branches") == ["main"]
  end
end
RUBY

if ! grep -Fq "script-test:" <<<"$script_test_section"; then
  echo "CI should run make script-test so workflow and publisher contract tests are not local-only"
  exit 1
fi

if ! grep -Fq "make script-test" <<<"$script_test_section"; then
  echo "script-test job should invoke make script-test"
  exit 1
fi

if ! grep -Fq "actions/setup-node" <<<"$script_test_section"; then
  echo "script-test job should install Node for JavaScript workflow tests"
  exit 1
fi

if grep -Fq '${{ secrets.' <<<"$script_test_section"; then
  echo "script-test must not reference secrets"
  exit 1
fi

if grep -Fq "metadata-gate:" "$workflow"; then
  echo "metadata-gate should not run alongside deterministic-gate because both would upload the same facts artifact"
  exit 1
fi

if grep -Fq "github.event.action != 'edited'" <<<"$fast_gate_section"; then
  echo "fast-gate must run on pull_request edited events so title/body edits cannot replace failed CI with a light success"
  exit 1
fi

for full_job in \
  "$unit_test_section" \
  "$lint_section" \
  "$script_test_section" \
  "$deterministic_section" \
  "$coverage_job_section" \
  "$dry_run_section" \
  "$security_section"; do
  if grep -Fq "github.event.action != 'edited'" <<<"$full_job"; then
    echo "full CI jobs must run on pull_request edited events; do not skip title/body-only edits"
    exit 1
  fi
done

for pull_request_job in "$deadcode_section" "$license_header_section"; do
  if grep -Fq "github.event.action != 'edited'" <<<"$pull_request_job"; then
    echo "pull_request-only CI jobs must run on edited events"
    exit 1
  fi
done

if grep -Fq '${{ secrets.' <<<"$deterministic_section"; then
  echo "deterministic-gate must not reference secrets"
  exit 1
fi

if ! grep -Fq "PUBLIC_CONTENT_METADATA=" <<<"$deterministic_section"; then
  echo "deterministic-gate should pass public content metadata into make quality-gate"
  exit 1
fi

if ! grep -Fq "PR_BRANCH:" <<<"$deterministic_section"; then
  echo "deterministic-gate should pass the pull request branch into public content metadata"
  exit 1
fi

if ! grep -Fq "name: quality-gate-facts-\${{ github.event.pull_request.base.sha }}-\${{ github.event.pull_request.head.sha }}" <<<"$deterministic_section"; then
  echo "deterministic-gate should upload base/head-bound quality-gate-facts for semantic review"
  exit 1
fi

if ! grep -Fq "needs: [unit-test, lint, script-test, deterministic-gate]" "$workflow"; then
  echo "E2E jobs should wait for script-test and deterministic-gate"
  exit 1
fi

if ! grep -Fq "script-test" <<<"$results_section"; then
  echo "results job should include script-test"
  exit 1
fi

if ! grep -Fq "deterministic-gate" <<<"$results_section"; then
  echo "results job should include deterministic-gate"
  exit 1
fi

if ! grep -Fq "timeout-minutes: 20" <<<"$dry_run_section"; then
  echo "e2e-dry-run should remain bounded at 20 minutes" >&2
  exit 1
fi

if ! grep -Fq "name: Resolve CLI E2E domains" <<<"$dry_run_section" ||
   ! grep -Fq "id: e2e_domains" <<<"$dry_run_section" ||
   ! grep -Fq "run: node scripts/e2e_domains.js" <<<"$dry_run_section"; then
  echo "e2e-dry-run should resolve changed-file CLI E2E domains before running tests"
  exit 1
fi

for validation_contract in \
  'case "$E2E_MODE" in' \
  'skip)' \
  '[ -z "$E2E_DRY_PACKAGES" ]' \
  'full|subset)' \
  '[ -n "$E2E_DRY_PACKAGES" ]' \
  'Invalid CLI E2E mode' \
  'exit 1'; do
  if ! grep -Fq "$validation_contract" <<<"$dry_run_section"; then
    echo "e2e-dry-run should fail invalid domain output before tests can be skipped: missing $validation_contract" >&2
    exit 1
  fi
done

if ! awk '
  /- name: Validate CLI E2E domain outputs/ { validated = 1 }
  /- name: Build lark-cli/ { exit validated ? 0 : 1 }
  END { if (!validated) exit 1 }
' <<<"$dry_run_section"; then
  echo "e2e-dry-run should validate domain outputs before building" >&2
  exit 1
fi

if ! grep -Fq "steps.e2e_domains.outputs.dry_packages" <<<"$dry_run_section"; then
  echo "e2e-dry-run should use resolved dry_packages instead of always running the full suite"
  exit 1
fi

if ! grep -Fq "E2E_REASON: \${{ steps.e2e_domains.outputs.reason }}" <<<"$dry_run_section" ||
   ! grep -Fq 'echo "Dry-run CLI E2E domains: $E2E_MODE ($E2E_REASON)"' <<<"$dry_run_section"; then
  echo "e2e-dry-run should pass dynamic domain output through env before shell use"
  exit 1
fi

if ! grep -Fq "E2E_DRY_ROOT_PACKAGE: \${{ steps.e2e_domains.outputs.dry_root_package }}" <<<"$dry_run_section" ||
   ! grep -Fq 'go test -v -count=1 -timeout=5m "$E2E_DRY_ROOT_PACKAGE"' <<<"$dry_run_section"; then
  echo "e2e-dry-run should run the root CLI E2E harness package without the DryRun/Regression filter"
  exit 1
fi

if ! grep -Fq "No dry-run CLI E2E needed" <<<"$dry_run_section"; then
  echo "e2e-dry-run should explicitly skip when domain mode is skip"
  exit 1
fi

if ! awk '
  /^      - name: Build lark-cli/ { in_step = 1 }
  in_step && /if: \$\{\{ steps\.e2e_domains\.outputs\.mode != '\''skip'\'' \}\}/ { found = 1 }
  in_step && /^      - name:/ && !/Build lark-cli/ { in_step = 0 }
  END { exit found ? 0 : 1 }
' <<<"$dry_run_section"; then
  echo "e2e-dry-run should skip building lark-cli when domain mode is skip"
  exit 1
fi

coverage_step="$(awk '
  /^      - name: Upload coverage to Codecov/ { in_step = 1 }
  in_step { print }
  in_step && /^      - name: Check coverage threshold/ { exit }
' "$workflow")"

if grep -Fq '${{ secrets.CODECOV_TOKEN }}' <<<"$coverage_step" &&
   ! grep -Fq "if: \${{ $fork_safe_guard }}" <<<"$coverage_step"; then
  echo "Codecov token should be available on push and same-repository pull_request, but not fork pull_request" >&2
  exit 1
fi

if ! awk -v guard="$fork_safe_guard" '
  /^  [A-Za-z0-9_-]+:/ {
    job_if = "";
    step_if = "";
  }
  /^    if:/ {
    job_if = $0;
  }
  /^      - (name|uses):/ {
    step_if = "";
  }
  /^        if:/ {
    step_if = $0;
  }
  /\$\{\{ secrets\./ {
    if (index(job_if, guard) || index(step_if, guard)) {
      next;
    }
    printf("secret reference at %s:%d must be guarded away from pull_request runs\n", FILENAME, FNR) > "/dev/stderr";
    bad = 1;
  }
  END { exit bad ? 1 : 0 }
' "$workflow"; then
  exit 1
fi

make_output="$(QUALITY_GATE_CHANGED_FROM= make -n quality-gate)"
for build_contract in \
  Makefile \
  build.sh \
  scripts/build-pkg-pr-new.sh \
  .goreleaser.yml \
  .github/workflows/ci.yml \
  .github/workflows/arch-audit.yml \
  .github/workflows/release.yml; do
  if grep -Fq "scripts/fetch_meta.py" "$build_contract"; then
    echo "$build_contract must build and test from the committed API catalog without fetch_meta.py"
    exit 1
  fi
done

if grep -Fq -- "--changed-from  \\" <<<"$make_output"; then
  echo "quality-gate should resolve an empty QUALITY_GATE_CHANGED_FROM before passing --changed-from"
  exit 1
fi

if ! grep -Fq "go run ./internal/qualitygate/cmd/manifest-export" <<<"$make_output"; then
  echo "quality-gate should generate command manifests through manifest-export"
  exit 1
fi

if ! grep -Fq -- "--public-content-metadata .tmp/quality-gate/public-content-metadata.json" <<<"$make_output"; then
  echo "quality-gate check should consume public content metadata"
  exit 1
fi

if ! grep -Fq -- "--manifest .tmp/quality-gate/command-manifest.json" <<<"$make_output" ||
   ! grep -Fq -- "--command-index .tmp/quality-gate/command-index.json" <<<"$make_output"; then
  echo "quality-gate check should consume both exported command snapshots"
  exit 1
fi

if ! awk '
  function finish_upload() {
    if (!in_upload) {
      return;
    }
    uploads++;
    if (path != ".tmp/quality-gate/facts.json") {
      printf("deterministic-gate upload-artifact path must be .tmp/quality-gate/facts.json, got %s\n", path) > "/dev/stderr";
      bad = 1;
    }
    in_upload = 0;
    path = "";
  }
  /^      - (name|uses):/ {
    finish_upload();
  }
  /uses: actions\/upload-artifact@/ {
    in_upload = 1;
  }
  in_upload && /^[[:space:]]*path:/ {
    path = $0;
    sub(/^[[:space:]]*path:[[:space:]]*/, "", path);
  }
  END {
    finish_upload();
    if (uploads == 0) {
      print "deterministic-gate should upload quality gate facts" > "/dev/stderr";
      bad = 1;
    }
    exit bad ? 1 : 0;
  }
' <<<"$deterministic_section"; then
  exit 1
fi
