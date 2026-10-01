# AGENTS.md

## Project

This repository automates installation and configuration of 3x-ui and related system components on Debian/Ubuntu servers.

The installer may run with root privileges and modify firewall rules, nginx, Fail2Ban, certificates, packages, system services, and 3x-ui configuration.

Treat this repository as security-sensitive infrastructure code.

## General principles

When making changes:

- prioritize security, reliability, idempotency, and maintainability;
- preserve the existing architecture unless there is a strong reason to change it;
- prefer small, understandable changes over large rewrites;
- do not introduce unnecessary dependencies or complexity;
- preserve backward compatibility where reasonably possible;
- do not weaken existing security defaults for convenience;
- assume the installer can be executed on an Internet-facing VPS.

Always consider the security implications of a change, even when the requested task is not explicitly security-related.

## Root execution

Assume installation scripts may execute as `root`.

Therefore treat all external input as untrusted, including:

- `.env` values;
- command-line arguments;
- environment variables;
- domains;
- ports;
- IP addresses and CIDRs;
- filesystem paths;
- URLs;
- downloaded files;
- upstream installer output.

Never allow untrusted input to become shell code.

## Shell safety

For Bash code:

- use `set -Eeuo pipefail` where appropriate;
- quote variable expansions unless word splitting is explicitly intended;
- prefer arrays for lists;
- avoid unsafe globbing and word splitting;
- never use `eval`;
- avoid dynamically constructed shell commands;
- use `mktemp` for temporary files;
- use `trap` for cleanup where appropriate;
- check return codes of security-critical commands;
- do not hide meaningful failures with `|| true`.

Run `bash -n` and ShellCheck against modified shell scripts when available.

Fix meaningful warnings rather than suppressing them without justification.

## Configuration files

Treat `.env` and other configuration files as **data, not executable shell code**.

Do not load configuration using:

```bash
source .env
. .env
eval ...
```

when the file can be influenced by the user.

Configuration parsing must not allow:

- command substitution;
- shell expansion;
- process substitution;
- arbitrary variable expansion;
- execution of Bash syntax.

Only supported configuration keys should be accepted.

Validate security-sensitive values before using them.

This includes at least:

- ports;
- domains;
- IP addresses;
- CIDRs;
- URLs;
- filesystem paths;
- booleans;
- durations;
- lists of ports.

Prefer failing with a clear error over silently accepting malformed security-sensitive configuration.

## Remote code and supply chain

Treat every remote download as a trust boundary.

Avoid patterns such as:

```bash
curl ... | bash
bash <(curl ...)
```

inside project implementation when a safer practical alternative exists.

Prefer:

1. downloading to a temporary file;
2. failing on HTTP errors;
3. HTTPS sources;
4. immutable versions, tags, or commit references where practical;
5. checksum/signature verification when authoritative verification data exists;
6. executing only after successful validation.

Never invent checksums or pretend that a download has been cryptographically verified when it has not.

Avoid silently tracking mutable upstream branches such as `master` or `main` for security-sensitive installers when an explicit version can reasonably be used.

Custom repository or installer URLs must not silently bypass security controls.

## Secrets

Never expose secrets unnecessarily.

Do not write the following into normal logs:

- passwords;
- API tokens;
- authorization headers;
- cookies;
- private keys;
- generated credentials;
- sensitive environment variables.

Verbose/debug modes must not leak secrets.

Sensitive files should have restrictive permissions.

Do not use broad recursive permission changes such as `chmod -R` on system directories.

## Filesystem safety

Be extremely careful with destructive filesystem operations.

Before using values in operations such as:

```bash
rm
rm -rf
cp
mv
ln
chmod
chown
```

validate the target.

Never allow an empty or unexpected variable to turn into deletion of a system directory.

For destructive paths:

- reject `/`;
- reject critical system directories;
- reject unexpected empty values;
- account for symlinks where relevant.

Prefer atomic configuration updates:

1. write a temporary file;
2. validate it;
3. preserve the previous valid configuration when appropriate;
4. move the new file into place;
5. reload the service only after validation succeeds.

Do not overwrite unrelated administrator-managed configuration.

## Firewall and networking

Firewall changes are security-critical.

The normal security posture should remain:

- deny unsolicited incoming traffic by default;
- allow outgoing traffic;
- expose only ports that are explicitly required.

Never open all ports as a workaround.

Do not reset an existing firewall unless explicitly requested.

Before modifying firewall rules, ensure that administrative SSH access will not accidentally be lost.

Do not assume SSH always listens on port 22.

The 3x-ui administrative panel must not become publicly accessible by default.

If panel exposure is explicitly requested, use the narrowest reasonable access rules and preserve protections such as TLS, strong credentials, Fail2Ban, and appropriate access restrictions.

## SSH safety

Do not automatically modify SSH security settings unless the requested task specifically requires it.

Do not silently:

- change the SSH port;
- disable password authentication;
- disable root login;
- replace `sshd_config`.

Any SSH hardening feature must minimize the risk of locking the administrator out.

Validate SSH configuration before applying or restarting it.

## nginx and TLS

Never reload nginx with an invalid configuration.

Validate nginx configuration before reload/restart.

Protect certificate private keys and other TLS secrets.

Do not disable certificate verification.

Do not weaken TLS configuration merely to make an installation succeed.

Do not enable potentially disruptive policies such as HSTS without considering their operational consequences.

## Fail2Ban

Prefer project-owned configuration under dedicated files rather than overwriting global administrator configuration.

Validate generated configuration where possible.

Do not disable existing protections unnecessarily.

## 3x-ui

Treat the 3x-ui administrative interface as sensitive.

Prefer secure defaults:

- no public panel exposure by default;
- strong randomly generated credentials;
- non-default/random web path where supported;
- TLS;
- TOTP/2FA where supported;
- Fail2Ban/login protection;
- supported and security-maintained upstream versions.

Never introduce predictable default credentials.

Do not sacrifice panel security merely to simplify installation.

## Idempotency

Installation and configuration code should be safe to run repeatedly.

Repeated execution must not unnecessarily:

- duplicate firewall rules;
- duplicate configuration entries;
- reissue certificates;
- regenerate credentials;
- destroy existing data;
- reinstall already-correct components;
- overwrite user customization.

Prefer converging the server toward the desired state rather than blindly repeating operations.

## Existing systems

Assume the target server may already contain:

- nginx configuration;
- certificates;
- firewall rules;
- Fail2Ban configuration;
- existing 3x-ui data;
- administrator-created files.

Do not assume the machine is disposable.

Preserve existing user data and unrelated configuration by default.

Destructive behavior must be explicit.

## Removal and cleanup

Uninstall/remove operations require the same level of care as installation.

Do not remove unrelated packages, certificates, configuration, web roots, or user data.

Distinguish project-managed resources from pre-existing resources whenever practical.

Destructive cleanup must be opt-in where data loss is possible.

## Service changes

When modifying service configuration:

- validate configuration before restart/reload;
- avoid restarting services unnecessarily;
- keep rollback/recovery possible;
- do not blindly apply systemd hardening options that could break required functionality.

Security controls must be compatible with the actual service behavior.

## Error handling

Failures should be explicit and actionable.

Critical operations should not silently continue after failure.

Error messages should make it clear:

- what failed;
- which component was affected;
- whether the previous configuration is still active;
- what the administrator should inspect.

Security-sensitive failures should normally fail closed rather than continuing with an insecure configuration.

## Logging

Logs should be useful for diagnosing installation failures without exposing sensitive information.

Prefer structured, concise messages.

Do not dump complete environments or configuration files into logs.

## Validation and testing

After modifying Bash code, run relevant checks available in the repository.

At minimum, where applicable:

```bash
bash -n <modified scripts>
shellcheck <modified scripts>
```

Run existing project tests related to the changed code.

When modifying parsers, path handling, firewall logic, removal logic, or other security-sensitive code, consider malicious and malformed input in addition to normal input.

## Scope discipline

Do not turn a small task into an unrelated system-hardening project.

Security improvements should address realistic risks introduced or affected by the current change.

Do not make unrelated operating-system changes unless they are required for the task.

Avoid speculative hardening that increases operational risk without a clear security benefit.

## Before finishing

Review the resulting diff for security regressions.

In particular, watch for:

- command injection;
- unsafe shell evaluation;
- unquoted variables;
- remote code execution;
- mutable remote dependencies;
- unsafe `rm -rf`;
- path traversal;
- secret leakage;
- overly permissive file modes;
- accidental firewall exposure;
- SSH lockout;
- destructive behavior;
- loss of idempotency.

If a requested implementation conflicts with these security principles, prefer a safer implementation that still satisfies the underlying requirement and briefly explain the difference.
