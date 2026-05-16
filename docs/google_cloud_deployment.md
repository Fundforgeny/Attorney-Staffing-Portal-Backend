# Google Cloud Deployment Notes

## Current deployment authority

The Attorney Staffing Portal backend / Fund Forge Rails backend is deployed on **Google Cloud Run**, not Render. The current backend Cloud Run service inspected during the May 16, 2026 deployment run is `fund-forge-app` in region `us-east4`, with health endpoint `https://fund-forge-app-3g3xvstryq-uk.a.run.app/up`.

| Resource | Current value |
| --- | --- |
| Google Cloud project | `titans-app-490313` |
| Backend Cloud Run service | `fund-forge-app` |
| Backend region | `us-east4` |
| Backend health endpoint | `https://fund-forge-app-3g3xvstryq-uk.a.run.app/up` |
| Sidekiq worker service | `fund-forge-sidekiq-worker` in `us-east4` |
| Primary database candidates observed | `fund-forge-postgres` in `us-east4`, `titans-db` in `us-central1`, `titans-test-db` in `us-central1` |
| GHL agency secret | Secret Manager secret `GHL_AGENCY_API_KEY` |

## Deployment command pattern

Deploy the latest local repo state to the backend service with Google Cloud CLI after authenticating through the approved service-account path:

```bash
gcloud config set project titans-app-490313
gcloud run deploy fund-forge-app \
  --region us-east4 \
  --source . \
  --allow-unauthenticated
```

Before deploying, validate the Rails code locally with the focused tests relevant to the change. For staffing/matter workflow work, at minimum run:

```bash
bundle _2.6.9_ exec rails test \
  test/integration/client_workflow_case_intakes_test.rb \
  test/services/connector_config_and_clio_sync_test.rb \
  test/services/google_secret_manager_secret_test.rb \
  test/services/talent_hub_ghl_config_test.rb
```

## Required runtime configuration

The service should use Google Cloud Secret Manager for live secrets. Do not store raw credential values in repository files or deployment docs.

| Runtime setting | Purpose |
| --- | --- |
| `GHL_AGENCY_API_KEY_SECRET_PROJECT=titans-app-490313` | Tells the app where to load the `GHL_AGENCY_API_KEY` Secret Manager secret. |
| `TITANS_LAW_GHL_LOCATION_ID=7b7kaqszIjsgIIPyjBUB` | Titans Law client sub-account location ID. |
| `TITANS_LAW_TALENT_HUB_LOCATION_ID=2ywU2OOzPzJIenESVkxz` | Titans Law Talent Hub sub-account location ID. |
| `GOOGLE_CLOUD_PROJECT=titans-app-490313` | General Google Cloud project context for runtime integrations. |
| `ACTIVE_STORAGE_SERVICE` | Optional. Leave unset for local disk storage unless a supported persistent object-storage backend is configured. |

The Cloud Run service account must have Secret Manager access to `GHL_AGENCY_API_KEY`. Grant access with the narrowest practical scope, for example at the secret level:

```bash
gcloud secrets add-iam-policy-binding GHL_AGENCY_API_KEY \
  --project titans-app-490313 \
  --member serviceAccount:<cloud-run-service-account> \
  --role roles/secretmanager.secretAccessor
```

## Validation after deployment

After deploy, validate the service in this order.

| Step | Command / check | Expected result |
| --- | --- | --- |
| Health | `curl https://fund-forge-app-3g3xvstryq-uk.a.run.app/up` | HTTP `200`. |
| Runtime env names | `gcloud run services describe fund-forge-app --region us-east4` | Required env names present; values must not be printed. |
| Secret access | App path that calls `GhlAgencyConfig.api_key` | Returns configured internally without logging the key. |
| Workflow intake | `POST /api/v1/workflows/client_case_intakes` with `X-Titans-Workflow-Token` | Creates or updates canonical `Case`, `CaseIntake`, `StaffingRequirement`, `ExternalSyncRecord`. |
| Clio preview | `POST /api/v1/admin/cases/:id/clio_sync_preview` | Returns dry-run Clio operations; does not write to Clio. |

## Deprecated Render references

Older docs and GitHub Actions may still contain Render references. Treat them as historical unless this file is explicitly superseded. Future deployment changes should update this document and the README in the same commit.
