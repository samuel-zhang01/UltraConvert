# Local CI

All automated checks and releases run on Samuel’s registered Mac runner
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
