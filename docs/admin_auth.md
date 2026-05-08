# Fund Forge Admin Authentication

Fund Forge admin access uses passwordless magic links for the SPA admin panel.

## Current Flow

1. Admin opens `https://payments.fundforge.net/admin/login`.
2. Admin enters an authorized email address.
3. Backend creates the admin user only when the email is allowlisted and no admin user exists yet.
4. Backend stores a one-time `AdminLoginLinkToken` digest and sends a 15-minute login link through the existing GHL/LeadConnector webhook delivery path used for customer login links.
5. Frontend verifies the token at `GET /api/v1/admin/login_link`.
6. Backend returns an admin JWT with `sub = admin:<id>`.
7. Frontend stores the token in `localStorage.auth_token` and uses it for admin API requests.

## Admin Roles

Fund Forge admin users now support three roles:

- `fund_forge_admin`: full access, including admin-user management, manual operations, and refunds
- `fund_forge_refunds`: read all Fund Forge data and issue refunds, but no other write actions
- `fund_forge_readonly`: read all Fund Forge data with no write actions

## Authorized Admin Bootstrap

`contact@fundforge.net` is the default allowlisted bootstrap admin email.

Bootstrap admins default to the `fund_forge_admin` role.

Optional environment settings:

- `ADMIN_MAGIC_LINK_EMAILS`: comma-separated list of admin emails allowed to self-bootstrap.
- `ADMIN_BOOTSTRAP_CONTACT_NUMBER`: contact number used for self-bootstrapped admin records.
- `FRONTEND_APP_URL` or `FRONTEND_BASE_URL`: base URL used when generating admin login links.
- `DEVISE_JWT_SECRET_KEY`: signing secret for admin JWTs.
- `MAILER_FROM`, `ACTION_MAILER_HOST`, and SMTP settings are only needed if Fund Forge later moves admin login-link delivery back to ActionMailer.

Do not use a shared default admin password. The `admin:create` rake task now requires `ADMIN_PASSWORD` to be provided explicitly if a password reset is ever intentionally performed by an operator.

## Secret Handling

Do not commit, paste, screenshot, or log raw passwords, JWT signing secrets, SMTP credentials, provider keys, or production database URLs.

Runtime secrets belong in the production host's approved secret store. Human/browser credentials belong in the approved password manager.
