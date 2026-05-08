# Fund Forge admin login delivery

Fund Forge admin magic links are currently delivered through the existing
LeadConnector / GoHighLevel webhook path.

Current delivery behavior:

1. Backend generates the admin login link
2. Backend posts the login link payload to the admin login GHL webhook
3. GHL workflow/template handles the outbound message

Admin login webhook URL:

- `https://services.leadconnectorhq.com/hooks/ypwiHcCIbSqZMzXzrIhd/webhook-trigger/d3d0e182-2544-4601-8ab5-636e9663c2f8`

Admin webhook payload fields:

- `email`
- `first_name`
- `last_name`
- `phone`
- `login_magic_link`
- `status=login`
- `portal_type=admin`

This avoids blocking admin login delivery on SMTP setup while Fund Forge is in
the middle of infrastructure transition work.
