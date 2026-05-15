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
