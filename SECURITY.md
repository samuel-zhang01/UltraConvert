# Security policy

In-app updates use Sparkle 2.10.0 from a checksum-pinned upstream distribution. Production feeds and downloads use HTTPS; the signed feed and Ed25519 archive signature are required, with verification before extraction. A signing failure never expires into an unsigned-feed fallback. Only the public update key is committed; the private signing key remains in the maintainer’s Keychain. Public app builds also require Developer ID signing, Hardened Runtime and Apple notarization.

The update archive includes the native app, Python conversion code and ImageMagick policy inside signed resources. External Homebrew engines, Python environment, preferences and saved folder rules remain outside the app. Updates do not silently upgrade those engines. Ad-hoc developer builds use a library-validation exception to load their framework; public release validation rejects unexpected entitlements, test-build provenance, incorrect update configuration or mismatched sealed conversion code.

Report suspected vulnerabilities privately through this repository's **Security → Report a vulnerability** page. Avoid public issues containing exploit files, secrets or private reports. Describe the affected version, reproduction and impact. The latest release receives fixes.

UltraConvert runs local third-party parsers/encoders with your user permissions. It is **not an operating-system sandbox**, and input guards do not make hostile files safe. Use a disposable VM or isolated account for untrusted files. Keep Homebrew engines current; pinned Python-package auditing does not cover every native engine or codec.

Implemented controls include argument-array subprocess calls, content probing, resource restrictions, safe YAML/XML parsing, archive limits/traversal refusal, local document resource confinement, disabled GIS schema/style fetching, controlled ImageMagick coders/delegates, bounded diagnostics, process-group cancellation, output staging and installation ownership/rollback. Known boundaries and checks are in [docs/AUDIT.md](docs/AUDIT.md).

Conversions have no app-level telemetry or upload path. Installation downloads dependencies. Conversion reports deliberately record local paths, engine arguments and errors; treat them as private until redacted.
