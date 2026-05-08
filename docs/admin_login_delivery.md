# Fund Forge admin login delivery

Fund Forge admin magic links are currently delivered through the existing
LeadConnector / GoHighLevel webhook path already used for customer login links.

Current delivery behavior:

1. Backend generates the admin login link
2. Backend posts the login link payload to the existing GHL webhook
3. GHL workflow/template handles the outbound message

Admin webhook payload fields:

- `email`
- `first_name`
- `last_name`
- `phone`
- `login_magic_link`
- `portal_type=admin`

This avoids blocking admin login delivery on SMTP setup while Fund Forge is in
the middle of infrastructure transition work.
