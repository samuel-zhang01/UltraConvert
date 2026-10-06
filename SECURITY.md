# Security policy

Report suspected vulnerabilities privately through this repository's **Security → Report a vulnerability** page. Avoid public issues containing exploit files, secrets or private reports. Describe the affected version, reproduction and impact. The latest release receives fixes.

UltraConvert runs local third-party parsers/encoders with your user permissions. It is **not an operating-system sandbox**, and input guards do not make hostile files safe. Use a disposable VM or isolated account for untrusted files. Keep Homebrew engines current; pinned Python-package auditing does not cover every native engine or codec.

Implemented controls include argument-array subprocess calls, content probing, resource restrictions, safe YAML/XML parsing, archive limits/traversal refusal, local document resource confinement, disabled GIS schema/style fetching, controlled ImageMagick coders/delegates, bounded diagnostics, process-group cancellation, output staging and installation ownership/rollback. Known boundaries and checks are in [docs/AUDIT.md](docs/AUDIT.md).

Conversions have no app-level telemetry or upload path. Installation downloads dependencies. Conversion reports deliberately record local paths, engine arguments and errors; treat them as private until redacted.
