# Local CI

Trusted main pushes and explicit main dispatches run the unchanged static gate
on `[deploy-vps, ultraconvert]` at 192.168.1.52 and the full native gate on
`[local-macos, ultraconvert]` on Samuel's ARM64 Mac. Public pull requests use
standard hosted runners, whose public-repository compute is free, keeping
external code off the owner's home machines. Runner labels select jobs; they
do not isolate repositories sharing the same user or host.

Native CI uses the installed Python 3.14 and public conversion engines with a
temporary virtual environment. It compiles an ad-hoc development app, creates
Finder actions in a disposable fixture home, runs both complete generated
format/edge suites, all six maintained Swift smoke suites, the security,
batch, installer, diagnostics, release and runtime suites, and the actual
setup checks against that fixture home. Native installer tests explicitly use
the freshly built app. UI tests use unique preference domains.

CI never invokes the user installer or the normal app entrypoint, registers
owner Finder services, replaces the installed app, reads owner automation
state, changes system packages, or signs with an owner credential. Temporary
builds and interpreter are removed. Generated JSON evidence has three-day
retention; artifact storage is distinct from runner compute billing.
