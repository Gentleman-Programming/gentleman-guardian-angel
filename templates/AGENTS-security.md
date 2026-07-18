# Security Audit — Code Review Rules

AI-powered pre-commit security audit based on OWASP Top 10:2025.

## Response Format

FIRST LINE must be exactly:
STATUS: PASSED
or
STATUS: FAILED

If FAILED, list each finding as:
`file:line - [A0X] Category - issue description - severity (CRITICAL/HIGH/MEDIUM/LOW)`

## A01: Broken Access Control

REJECT if:
- Missing authorization check on any endpoint, route, or function that accesses protected resources
- Direct object reference (IDOR) without ownership verification (e.g., `getUser(req.params.id)` without checking `req.user.id === params.id`)
- Role escalation possible through user-controlled input (e.g., `user.role = req.body.role`)
- CORS `Access-Control-Allow-Origin: *` combined with credentials
- Missing access control on admin/internal API routes
- Session token accepted from URL parameter or query string
- Privilege check bypass via HTTP method override (e.g., `_method=DELETE`)
- Directory traversal via unsanitized path input (e.g., `fs.readFile(req.query.file)`)
- Server-Side Request Forgery (SSRF): server makes outbound requests to attacker-controlled URLs (e.g., `fetch(req.query.url)` without an allow-list)

PREFER:
- Explicit allow-list for roles and permissions
- Ownership verification: `if (resource.ownerId !== currentUser.id) return 403`
- Server-side session validation on every request
- Deny by default, allow by explicit policy

## A02: Security Misconfiguration

REJECT if:
- Debug mode enabled in production config (e.g., `DEBUG=True`, `app.debug = true`)
- Default credentials present (e.g., `admin/admin`, `password`, `changeme`)
- Security headers missing in server config:
  - `Strict-Transport-Security` (HSTS)
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY` or `SAMEORIGIN`
  - `Content-Security-Policy`
- Detailed error messages exposed to client (stack traces, internal paths, SQL errors)
- Unnecessary HTTP methods enabled (TRACE, PUT, DELETE when not used)
- Open cloud storage buckets (S3, GCS, Azure Blob) without access policy
- Default security keys shipped in code (framework defaults, example keys)
- Feature flags or admin panels exposed without authentication

PREFER:
- Environment-based configuration with separate prod/dev profiles
- Minimal attack surface — disable unused features, routes, plugins
- Custom error pages with generic messages; log details server-side only
- Security headers enforced at reverse proxy or middleware level

## A03: Software Supply Chain Failures

REJECT if:
- Dependency pinned to a version with known critical CVE (check `npm audit`, `pip-audit`, `govulncheck`, `cargo audit`)
- `eval()`, `Function()`, or `child_process.exec()` used to execute untrusted code
- Package installed from non-official source (e.g., `pip install` from raw GitHub URL without hash verification)
- Subresource Integrity (SRI) hash missing on external script/style tags
- CI/CD pipeline runs without dependency verification or signature checking
- Docker image built from `:latest` tag instead of pinned version
- `depends-on` or `extends` references unverified external CI/CD actions

PREFER:
- Lockfiles committed and enforced (`package-lock.json`, `poetry.lock`, `go.sum`)
- Dependabot/Renovate or equivalent automated dependency scanning
- Pinned versions with SHA digests for Docker images
- SRI hashes on all CDN-hosted assets

## A04: Cryptographic Failures

REJECT if:
- Passwords hashed with MD5, SHA-1, or plain text
- Weak KDF without work factor (use bcrypt, scrypt, or Argon2id with appropriate cost)
- Hardcoded encryption keys, API keys, or secrets in source code
- Weak random number generator used for security-sensitive values (use `crypto.randomBytes`, not `Math.random`)
- TLS version below 1.2 allowed
- Sensitive data transmitted over unencrypted channel (HTTP instead of HTTPS)
- Encryption mode ECB used for multi-block data
- JWT signed with `none` algorithm or symmetric key hardcoded in source
- Salt reused across multiple passwords or too short (< 16 bytes)

PREFER:
- bcrypt/Argon2id with cost >= 12 for password hashing
- Secrets loaded from environment variables or secret manager (Vault, AWS Secrets Manager)
- TLS 1.3 enforced with forward secrecy
- AES-256-GCM or ChaCha20-Poly1305 for symmetric encryption
- JWT with RS256/ES256 and short expiry + refresh token rotation

## A05: Injection

REJECT if:
- SQL queries built via string concatenation with user input (e.g., `query("SELECT * FROM users WHERE id = " + req.params.id)`)
- NoSQL injection via unsanitized object input (e.g., `User.find({ $where: req.body.search })`)
- OS command injection via `exec()`, `system()`, `subprocess.run()` with shell=True and user input
- Template injection via user input in template engine (e.g., Jinja2 `render_template_string(user_input)`)
- LDAP injection via unsanitized DN construction
- XPath injection via unsanitized XPath query construction
- ORM raw queries with string interpolation instead of parameterized inputs
- Log injection via unsanitized user input in log statements (e.g., `\n` injection to forge log entries)

PREFER:
- Parameterized queries / prepared statements for ALL database access
- ORM query builders that parameterize by default
- Allow-list input validation for special characters
- Shell execution with argument arrays (e.g., `subprocess.run(["cmd", arg])` without `shell=True`)

## A06: Insecure Design

REJECT if:
- No rate limiting on authentication, password reset, or registration endpoints
- Business logic without server-side validation (client-side validation only)
- Lack of transaction limits or anti-fraud checks on financial operations
- Predictable identifiers for security-sensitive resources (sequential IDs for session tokens, reset codes)
- Missing CSRF protection on state-changing POST/PUT/DELETE requests
- Lack of account lockout or progressive delay after failed login attempts
- Unlimited file upload without type/size validation
- Workflow steps that can be skipped or executed out of order

PREFER:
- Threat modeling before implementation for critical features
- Rate limiting middleware on all public endpoints (e.g., express-rate-limit, slowapi)
- Server-side validation with allow-list approach
- Cryptographically random IDs for external-facing resources
- CSRF tokens on all state-changing forms

## A07: Authentication Failures

REJECT if:
- Session IDs that don't rotate after login
- Session fixation possible (session ID accepted from URL or not regenerated on auth)
- JWT without expiration claim (`exp`)
- Refresh tokens stored in localStorage (use httpOnly cookies)
- Password reset token that doesn't expire or is reusable
- Credentials transmitted without TLS
- Weak password policy (no minimum length, allows common passwords like `123456`, `password`)
- Multi-factor authentication bypass possible via direct page access
- Session timeout missing or too long (> 8 hours for sensitive apps)

PREFER:
- Session ID regeneration on every privilege change
- JWT with short expiry (<= 15 min) + refresh token rotation
- Secure, httpOnly, SameSite cookies for session storage
- Password reset tokens: single-use, short expiry (<= 15 min), bound to user identity
- Minimum 12-character passwords with breach-database check (haveibeenpwned API)

## A08: Software or Data Integrity Failures

REJECT if:
- Deserialization of untrusted data without type verification (e.g., `pickle.loads(user_data)`, `JSON.parse` without schema validation for sensitive fields)
- CI/CD pipeline without branch protection (can push directly to main)
- Auto-update mechanism without signature verification (e.g., downloading and executing updates without checksum)
- WebAssembly or dynamic code loading from untrusted source
- CI secrets exposed in build logs or accessible in pull_request_target workflows
- Unsigned commits merged to protected branches (require signed commits on main)

PREFER:
- Schema validation on all deserialized input (Zod, Pydantic, JSON Schema)
- Branch protection rules: require PR review, status checks, signed commits
- Code signing for releases and updates
- CI/CD secrets scoped to specific jobs, never printed, masked in logs

## A09: Security Logging and Alerting Failures

REJECT if:
- No logging of authentication events (login success/failure, logout, password change)
- No logging of access control failures (403 responses, unauthorized access attempts)
- Logs containing sensitive data (passwords, tokens, PII, credit card numbers)
- Log injection possible via unsanitized user input in log messages
- No log integrity protection (logs can be modified or deleted without detection)
- No alerting on suspicious patterns (brute force, privilege escalation, mass data access)
- Audit trail missing for data modification operations (who changed what, when)

PREFER:
- Structured logging (JSON) with consistent fields (timestamp, user, action, resource, IP)
- Log sanitization: strip or mask sensitive fields before logging
- Centralized log aggregation with tamper protection (append-only, WORM storage)
- Alerting on: repeated auth failures, access control denials, unusual data access patterns
- Retention policy aligned with compliance requirements (e.g., 90 days minimum for SOC 2)

## A10: Mishandling of Exceptional Conditions

REJECT if:
- Empty catch/except blocks that silently swallow errors (e.g., `catch (e) {}` with no logging)
- Generic exception handlers that expose internal details to client (e.g., `catch (e) { res.json(e) }`)
- State left inconsistent after exception (e.g., partial database write without rollback)
- Resource leaks after error (unclosed file handles, connections, locks)
- Error handling that varies by input in a way that leaks information (timing attacks, different error messages for valid vs invalid usernames)
- Unhandled promise rejections or uncaught exceptions in Node.js/Go that crash the process without recovery
- Fallback to insecure behavior when secure path fails (e.g., TLS fails -> retry over HTTP)

PREFER:
- Catch specific exceptions, not broad `catch (Exception e)` that hides bugs
- Log error with context, return generic message to client
- Use transactions for multi-step state changes with automatic rollback
- Try-finally or language-equivalent for resource cleanup
- Uniform error responses that don't leak internal state
- Circuit breakers and graceful degradation for dependency failures

## General Security Rules (Always Apply)

REJECT if:
- Hardcoded secrets, API keys, passwords, or tokens in source code
- `eval()`, `new Function()`, or equivalent dynamic code execution with user input
- `dangerouslySetInnerHTML` (React), `v-html` (Vue), or innerHTML with unsanitized user input
- Secrets in client-side code (anything shipped to browser is public)
- `console.log` of sensitive data (tokens, passwords, PII) in production code
- HTTP (not HTTPS) for any external API call or redirect
- Regular expressions susceptible to ReDoS (catastrophic backtracking)
- File operations without path canonicalization (normalize + resolve before access)

## Severity Classification

| Severity | Criteria |
|----------|----------|
| CRITICAL | Remote code execution, auth bypass, secret exposure, SQL injection with data exfiltration |
| HIGH | Privilege escalation, IDOR with sensitive data, broken crypto, missing auth on sensitive endpoint |
| MEDIUM | Missing rate limiting, information disclosure, weak logging, missing security headers |
| LOW | Missing input validation on non-sensitive field, verbose error messages, minor config issues |
