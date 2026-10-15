# Local CI

All project-defined checks and releases run on Samuel’s registered Mac runner
`samuel-mac-ultraconvert`, selected by `[ultraconvert, local-macos]`.
There are no GitHub-hosted runner fallbacks. Jobs queue while this Mac is
asleep or offline; GitHub does not substitute a hosted machine.

Only owner-triggered main pushes, main dispatches and version-tag validation
run on this Mac. Public pull requests do not start CI: review external changes
and run them in a disposable environment before merging. Runner labels select
jobs; they do not isolate repositories sharing the same user or host.

Native CI uses the installed Python 3.14 and public conversion engines with a
temporary virtual environment. It compiles an ad-hoc development app, creates
Finder actions in a disposable fixture home, runs both complete generated
format/edge suites, all maintained Swift smoke suites, the security,
batch, installer, diagnostics, release and runtime suites, and the actual
setup checks against that fixture home. Native installer tests explicitly use
the freshly built app. UI tests use unique preference domains.

CI never invokes the user installer or the normal app entrypoint, registers
owner Finder services, replaces the installed app, reads owner automation
state, changes system packages, or signs with an owner credential. Temporary
builds and interpreter are removed. Generated JSON evidence has three-day
retention; artifact storage is distinct from runner compute billing.

GitHub-managed Dependabot and Dependency Graph jobs are separate from these
project workflows. They can still appear on GitHub-hosted Linux infrastructure;
standard Dependabot usage is free and GitHub does not support Dependabot on
self-hosted runners for public repositories. Dependency alerts remain enabled.
See [GitHub’s Dependabot compute notice](https://github.blog/changelog/2025-06-23-upcoming-change-dependabot-compute-migration-to-github-actions/)
and [runner limitations](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-on-actions).
No billed macOS runner is selected by this project’s workflows. This runner
policy does not set an account-wide spending limit or cover other repositories.
