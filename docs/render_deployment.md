# Render deployment notes

## Current Render resources

- Web service URL: `https://attorney-staffing-portal-backend-1.onrender.com`
- Web service ID: `srv-d5b88h63jp1c73d3fu60`
- Postgres database ID: `dpg-d5b5bmf5r7bs73a5p990-a`

## App/database wiring

The Rails app reads `DATABASE_URL` in staging and production, so the Render web service should have the database wired through that environment variable.

Recommended setup:

- Set the Render web service `DATABASE_URL` to the **internal** Render Postgres connection string.
- Use the **external** Render Postgres connection string only for local tools like `psql`, pgAdmin, TablePlus, or DBeaver.

## Render dashboard steps

1. Open the Render web service with ID `srv-d5b88h63jp1c73d3fu60`.
2. Open **Environment**.
3. Verify `DATABASE_URL` is present and points to the internal Postgres URL.
4. Trigger a redeploy after any environment changes.

## Render API examples

Inspect the web service:

```bash
curl -s https://api.render.com/v1/services/srv-d5b88h63jp1c73d3fu60 \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $RENDER_API_KEY"
```

List services:

```bash
curl -s https://api.render.com/v1/services \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $RENDER_API_KEY"
```

## Security notes

- Do not store live API keys, database passwords, or PATs in the repository.
- If credentials were pasted into chat or shared in plaintext, rotate them.
