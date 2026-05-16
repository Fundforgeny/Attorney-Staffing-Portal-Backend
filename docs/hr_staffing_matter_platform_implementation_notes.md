# HR Staffing & Matter Platform Implementation Notes

**Author:** Manus AI
**Date:** May 15, 2026
**Related plan:** [`docs/hr_staffing_matter_platform_build_plan.md`](./hr_staffing_matter_platform_build_plan.md)

## First Foundation Slice

The first implementation slice adds backend foundations for the canonical Titans Law matter and staffing layer. The work intentionally avoids live Clio, GoHighLevel, Talent Hub, and Indeed API calls. It also avoids storing raw credentials. The Talent Hub GHL token should be supplied only through the approved runtime secret mechanism as `TITANS_LAW_TALENT_HUB_GHL_API_KEY`, and the Talent Hub location ID should be supplied as `TITANS_LAW_TALENT_HUB_LOCATION_ID` unless later deployment docs define different names.

| Area | Implementation status |
| --- | --- |
| `Case` model | Replaced the stale `Client` association with schema-aligned associations for `firm`, `created_by`, `assigned_user`, `client_user`, intake records, related parties, tasks, staffing requirements, and sync records. |
| Matter intake | Added `CaseIntake` with review status, source, transcript, raw payload, AI extraction JSON, reviewer metadata, and Active Storage attachments for intake form, call recording, and matter packet. |
| Related parties | Added `RelatedParty` for parties, counsel, role metadata, and future Clio contact linkage. |
| Case tasks | Added `CaseTask` for AI-generated and staff-created next steps, including priority, status, source, due date, owner, and Clio task ID. |
| Staffing requirements | Added `StaffingRequirement` for required license states, federal court admissions, practice areas, urgency, residency requirement, and target interview count. |
| Field mapping | Added `FieldMapping` for mapping existing GHL/Talent Hub custom fields to canonical Titans attributes. |
| External sync tracking | Added `ExternalSyncRecord` for idempotent Clio/GHL/Indeed/Titans app sync tracking. |
| Talent Hub connector config | Added `TalentHubGhlConfig`, which reads only the named environment variables and returns a `GhlService` instance when configured. |
| Attorney resumes | Added an Active Storage `resume` attachment to `AttorneyProfile` for the later Indeed resume parser/import workflow. |
| Admin cases API | Added authenticated read endpoints at `GET /api/v1/admin/cases` and `GET /api/v1/admin/cases/:id` for case queue and case detail visibility. |
| Admin staffing requirements API | Added authenticated read endpoints at `GET /api/v1/admin/staffing_requirements` and `GET /api/v1/admin/staffing_requirements/:id` for staffing queue visibility. |

## Validation Notes

The sandbox did not initially include a Rails-compatible Ruby runtime. Ruby 3.3.11 was installed with rbenv, Bundler 2.6.9 was installed to match the lockfile, and local PostgreSQL and Redis services were started so migrations and focused tests could run. The repository now includes `.ruby-version` with `3.3.11` to make the local validation runtime explicit for future agents.

| Validation | Result |
| --- | --- |
| Ruby syntax checks on new/modified Ruby files | Passed. |
| Test database migration | Passed with Ruby 3.3.11, Bundler 2.6.9, local PostgreSQL, and local Redis. |
| Focused Rails tests | Passed: `14 runs, 63 assertions, 0 failures, 0 errors, 0 skips`. |
| Secret leakage check | Passed: the provided Talent Hub token prefix was not found in `README.md`, `docs`, `app`, `config`, `db`, or `test`. |

## Commands Run

```bash
ruby -c db/migrate/20260515223000_add_staffing_matter_foundation.rb
ruby -c app/models/case.rb
ruby -c app/models/case_intake.rb
ruby -c app/models/related_party.rb
ruby -c app/models/case_task.rb
ruby -c app/models/staffing_requirement.rb
ruby -c app/models/field_mapping.rb
ruby -c app/models/external_sync_record.rb
ruby -c app/services/talent_hub_ghl_config.rb
ruby -c test/models/staffing_foundation_test.rb
ruby -c test/services/talent_hub_ghl_config_test.rb
```

The focused Rails test commands to rerun are:

```bash
bin/rails test test/models/staffing_foundation_test.rb test/services/talent_hub_ghl_config_test.rb
bin/rails test test/models/staffing_foundation_test.rb test/services/talent_hub_ghl_config_test.rb test/integration/admin_cases_and_staffing_requirements_test.rb
```

## Next Implementation Step

The next safe slice should add create/update workflows for case intake review and staffing requirements, then connect reviewed case packets to the Clio dry-run/sync service. Do not implement live Talent Hub writes until `TITANS_LAW_TALENT_HUB_GHL_API_KEY` and `TITANS_LAW_TALENT_HUB_LOCATION_ID` are present in the approved runtime secret store.

## Build 1: Client Workflow API Trigger

Build 1 now supports an inbound API call from the Titans Law client workflow when a contact changes into the **customer** contact type. This endpoint is designed for the workflow located at Titans Law location `7b7kaqszIjsgIIPyjBUB`, workflow `69273f4c-6f78-4fc4-9953-621497e018b6`. The browser session could not open the workflow page in this run because no browser window was available, so the implementation is based on the user-provided workflow URL and the stated trigger rule.

| Item | Implementation detail |
| --- | --- |
| Endpoint | `POST /api/v1/workflows/client_case_intakes` |
| Auth | Send `X-Titans-Workflow-Token: <runtime secret>` or `Authorization: Bearer <runtime secret>`. The backend reads the expected token from `TITANS_CLIENT_WORKFLOW_API_TOKEN`. |
| Trigger | Intended to run when the client workflow detects a customer contact type change. Supported contact types remain `lead`, `consult booked`, and `customer`; a paid contact should move to `customer`. |
| Idempotency | Prefer sending `external_event_id`. If unavailable, the service derives an event ID from `workflow_id`, `ghl_contact_id`, and the new contact type. |
| Canonical records created/updated | `User`, `Firm`, `Case`, `CaseIntake`, `StaffingRequirement`, `RelatedParty`, `CaseTask`, and `ExternalSyncRecord`. |
| Ads reporting API data | Include ads reporting/attribution data under `ads_attribution`, `ad_attribution`, `ads_reporting`, or `utm`; the payload is stored in `cases.custom_data` and `staffing_requirements.custom_data` for later reporting. |

Example workflow payload shape:

```json
{
  "workflow_id": "69273f4c-6f78-4fc4-9953-621497e018b6",
  "workflow_name": "Client Paid - Open Matter",
  "location_id": "7b7kaqszIjsgIIPyjBUB",
  "ghl_contact_id": "{{contact.id}}",
  "ghl_opportunity_id": "{{opportunity.id}}",
  "trigger": { "type": "contact_type_change", "field": "contact_type" },
  "contact_type_change": {
    "previous_contact_type": "lead",
    "new_contact_type": "customer"
  },
  "client": {
    "email": "{{contact.email}}",
    "first_name": "{{contact.first_name}}",
    "last_name": "{{contact.last_name}}",
    "phone": "{{contact.phone}}"
  },
  "case": {
    "title": "{{contact.full_name}} Matter",
    "description": "{{custom.case_text}}",
    "jurisdiction": "{{custom.jurisdiction}}",
    "county": "{{custom.county}}",
    "zip_code": "{{contact.postal_code}}",
    "practice_areas": ["{{custom.practice_area}}"],
    "retainer_amount": "{{custom.retainer_amount}}",
    "budget_amount": "{{custom.budget_amount}}"
  },
  "intake": {
    "transcript": "{{custom.call_transcript}}",
    "ai_extraction": {}
  },
  "staffing_requirement": {
    "status": "ready",
    "urgency": "urgent",
    "required_license_states": ["{{custom.jurisdiction}}"],
    "practice_areas": ["{{custom.practice_area}}"],
    "target_interview_count": 5
  },
  "ads_attribution": {
    "source": "{{attribution.source}}",
    "campaign_id": "{{attribution.campaign_id}}",
    "ad_group_id": "{{attribution.ad_group_id}}",
    "ad_id": "{{attribution.ad_id}}",
    "gclid": "{{contact.gclid}}"
  }
}
```

The next build should connect this created `CaseIntake` to the AI extraction/review and Clio dry-run/sync workflow. Live outbound GHL/Talent Hub writes should remain blocked until the Talent Hub API key, Talent Hub location ID, and existing custom field mapping inventory are confirmed in the approved runtime secret store and `FieldMapping` records.

## Local Workflow Run Result

The Build 1 endpoint was run locally with a safe customer contact type change payload. Development Active Storage now defaults to local disk storage through `config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym`, so local workflow execution no longer requires legacy AWS credentials. If a future environment intentionally needs S3, it can set `ACTIVE_STORAGE_SERVICE=amazon` and provide the required AWS variables; otherwise AWS should not block the staffing/matter workflow path.

| Check | Result |
| --- | --- |
| Endpoint called | `POST /api/v1/workflows/client_case_intakes` |
| Trigger simulated | Customer contact type change from `lead` to `customer` for workflow `69273f4c-6f78-4fc4-9953-621497e018b6`. |
| First run | Returned `201 Created` with message `Case intake created.` |
| Replay/idempotency run | Returned `200 OK` with message `Case intake updated.` |
| Canonical case | Created case `Workflow Local Test Matter` with jurisdiction `SC`, county `Richland`, budget `5000`, and retainer `5000`. |
| Intake/staffing records | Created one `CaseIntake`, one `StaffingRequirement`, one `RelatedParty`, one `CaseTask`, and one `ExternalSyncRecord`. |
| Ads attribution | Persisted `ads_attribution.source = google` in canonical case custom data. |
| Contact type | Persisted `contact_type_change.new_contact_type = customer` in canonical case custom data. |

The local payload file used for this sandbox run was temporary (`tmp_client_workflow_payload.json`) and should not be committed. Future live runs should call the same endpoint from the Titans Law workflow using the runtime secret `TITANS_CLIENT_WORKFLOW_API_TOKEN` and real workflow merge fields.

## Connector Layer: Clio Preview and Agency-Level GHL Access

The connector layer now has a safe foundation for **Clio matter sync previews** and **agency-level GoHighLevel credential resolution**. Live writes remain intentionally gated until runtime secrets and payload approval rules are confirmed, but staff/admin users can now preview what the Clio sync service would attempt before any external Clio mutation occurs.

| Area | Implementation detail |
| --- | --- |
| Agency GHL key | `GhlAgencyConfig` reads one agency credential from `GHL_AGENCY_API_KEY`. There is no default location assumption because each firm/sub-account has its own GHL `location_id`; connector calls must pass `firm.location_id` or another explicit location ID. Optional `TITANS_LAW_GHL_LOCATION_ID` may identify the Titans Law client sub-account for workflows that are not tied to a `Firm` row. |
| Talent Hub fallback | `TalentHubGhlConfig` still requires `TITANS_LAW_TALENT_HUB_LOCATION_ID`; the Talent Hub location ID is `2ywU2OOzPzJIenESVkxz`. It can use `GHL_AGENCY_API_KEY` when a separate `TITANS_LAW_TALENT_HUB_GHL_API_KEY` is not present. This keeps the Talent Hub location separate while centralizing credentials. |
| Clio runtime token | `ClioConfig` reads `CLIO_ACCESS_TOKEN` and optional `CLIO_API_BASE_URL`, defaulting to `https://app.clio.com/api/v4`. Raw Clio tokens must stay in the approved runtime secret store, never in repo files. |
| Clio dry-run service | `ClioMatterSyncService#dry_run` builds deterministic operations for client contact, matter, note, related contacts, and tasks from canonical `Case`, `CaseIntake`, `RelatedParty`, and `CaseTask` records. |
| Admin preview endpoint | `POST /api/v1/admin/cases/:id/clio_sync_preview` returns the Clio operation packet for review. It does not write to Clio. |

The next connector step is to verify the exact Clio field/custom-field payloads in a sandbox or approved live test matter, then replace the live-write gate in `ClioMatterSyncService#sync!` with idempotent API calls and `ExternalSyncRecord` updates. GHL outbound writes should use `GhlAgencyConfig.ghl_service_for_firm(firm)` when a `Firm` row owns the sub-account, `GhlAgencyConfig.ghl_service(location_id: explicit_location_id)` when the caller already knows the sub-account, and `TalentHubGhlConfig.ghl_service` for Talent Hub operations.

A GHL agency key was pasted into chat during implementation. Treat that value as exposed: do not copy it into shell commands, files, Git history, logs, or docs. Rotate it and enter the replacement value directly into the approved runtime secret store as `GHL_AGENCY_API_KEY`.

## Live Recent-Customer Run Blocker

A live run was requested to pull recent contacts from the Titans Law sub-account whose contact type recently became `customer` and run them through the workflow intake path. The backend runtime was checked without printing secret values. The Titans Law `Firm` row exists and has a `location_id`, but `GHL_AGENCY_API_KEY` is not present in the Rails runtime environment, and no GHL connector secret was available through the local connector configuration search.

| Check | Result |
| --- | --- |
| `GHL_AGENCY_API_KEY` runtime env | Missing. |
| `TITANS_LAW_GHL_LOCATION_ID` runtime env | Missing. |
| Titans Law `Firm` row | Present. |
| Titans Law `Firm.location_id` | Present. |
| Talent Hub location ID | Documented as `2ywU2OOzPzJIenESVkxz`. |
| Safe run status | Blocked until a rotated agency key is entered directly into the approved secret store as `GHL_AGENCY_API_KEY`. |

The agency key pasted in chat must be treated as exposed and should not be used for live pulls. Rotate it, enter the replacement directly into the approved runtime secret store, and then rerun the recent-customer pull using `GhlAgencyConfig.ghl_service_for_firm(titans_law_firm)`.
