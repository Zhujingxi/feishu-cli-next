# CI execution

Repository workflows run on a repository-scoped Linux x64 self-hosted runner
with labels `[self-hosted, linux, x64, feishu-ci]`. This includes the required
`results` and `offline` checks, scheduled audits, labeling and review automation.
One runner executes one job at a time; jobs waiting for it remain queued. Keep
the existing checks, permissions, offline isolation and evidence artifacts.

The runner supplies Git, GCC, Make, Python 3.12 in the Actions tool cache, Node,
Ruby, `bc`, the GitHub CLI and Docker. Workflow setup actions continue to select
their declared Go/Node/Python versions. Go build/module and Actions tool caches
persist on the runner. `setup-go` disables the redundant Actions cache transfer;
the local Go caches remain active. Temporary job data belongs under `RUNNER_TEMP`, which
the Actions runner cleans between jobs. Do not put tokens or machine addresses
in this public repository.

External fork workflows require approval from a maintainer on every contribution;
review the code and workflow changes before approving execution on this runner.
Privileged `pull_request_target` and `workflow_run` jobs must continue to use
verified base-branch code and treat PR data/artifacts as untrusted input.

The release and preview publication gates remain deliberately disabled until
publication-channel acceptance. The dormant release workflow retains its macOS
signing/notarization verification and publication runner contracts; those tasks
cannot be moved to a Linux runner by changing labels. GitHub-managed Dependabot
and dependency-graph jobs are separate from the checked-in workflows and remain
managed by GitHub for this public repository.

When the self-hosted runner is offline, restore that runner rather than removing
required checks or silently selecting a GitHub-hosted fallback. The workflow
contract checks in `make script-test` reject a routing change in any workflow
other than the paused release workflow.
