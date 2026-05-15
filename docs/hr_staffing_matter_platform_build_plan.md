# Titans Law HR Staffing & Matter Platform Build Plan

**Author:** Manus AI  
**Date:** May 15, 2026  
**Status:** Planning document for implementation sequencing  
**Source-of-truth location:** `docs/hr_staffing_matter_platform_build_plan.md`

## Executive Summary

Titans Law needs the next platform layer to connect **paid client intake**, **Clio matter creation**, **AI case analysis**, **attorney recruiting**, **case-opportunity distribution**, and **attorney staffing decisions** into one operational system. The near-term system must work with the current **Clio** and **GoHighLevel / Titans Law Talent Hub** stack, while the long-term design must avoid hard-coding Clio or GHL as permanent sources of truth. The correct architecture is therefore a **canonical Titans case and staffing layer** that writes outward to Clio and GoHighLevel during the interim period, then later redirects the same services into the Titans app without rebuilding the workflow.

The meeting notes describe the current manual operating model: when a client pays, staff should gather the intake form and call recording, use Gemini to extract parties, jurisdiction, case description, and next steps, create a Clio matter, set the retainer/budget, and then staff the case through the Talent Hub or Indeed when internal matches are insufficient.[1] The current backend already contains several reusable foundations, including Rails, Active Storage, firm/sub-account modeling, GHL contact linkage, attorney profile fields, and a preliminary `cases` table with `clio_matter_id`, `jurisdiction`, `practice_areas`, and assignment fields.[2] However, the current API surface remains payment/admin/customer-portal centric and does not yet expose the required staffing, candidate, resume, interview, case opportunity, attorney interest, Clio sync, or Indeed ingestion endpoints.[3]

The user has clarified that **the relevant GoHighLevel custom fields already exist**. Therefore, the build should not spend time recreating those fields. It should create a **field mapping registry** that records the existing Talent Hub field names and field IDs, maps them into canonical Titans attributes, and uses that map for syncing until the Titans app replaces GHL.

## Product Thesis

Titans Law is not simply adding a recruiting portal. It is building a **matter-to-staffing operating system**. The core business event is not “candidate applied” or “matter opened”; it is **paid client requires attorney coverage**. Every module should serve that event. The platform should know what legal matter exists, where it belongs, what type of attorney is required, which attorneys are eligible, who was contacted, who expressed interest, who interviewed, who accepted, who was assigned, and whether the matter later needs restaffing.

> **Working definition:** A staffed matter is a paid client matter with a canonical Titans case record, a synchronized Clio matter while Clio remains active, at least one accountable attorney assignment, and an auditable staffing trail showing candidate matching, outreach, interest, interview, acceptance, and restaffing history.

The long-term advantage of this design is that the same workflow supports three operating states. First, it supports today’s manual-heavy process in Clio and GHL. Second, it supports a hybrid period where Titans automates matter creation, AI summaries, outreach, resume parsing, and opportunity matching while still writing to Clio and GHL. Third, it supports the future cutover where the Titans app becomes the operational source of truth and Clio/GHL are either read-only archives or removed from the workflow.

| Operating period | Source of truth | External systems | Platform behavior |
| --- | --- | --- | --- |
| Current manual period | GHL + Clio + staff knowledge | GHL, Clio, Indeed | Staff manually creates matters, filters Talent Hub contacts, posts Indeed jobs, and moves candidates through GHL stages. |
| Hybrid automation period | Titans backend canonical records | Clio, GHL, Indeed dashboard/API | Titans creates canonical cases, syncs to Clio, maps to existing GHL fields, automates candidate intake, and tracks staffing decisions. |
| Future Titans app period | Titans app | Optional Clio/GHL archive or connectors | Titans owns matter management, attorney portal, staffing marketplace, communications, task generation, and analytics. |

## Source Evidence and Constraints

The current Rails backend is documented as the backend for payments, customer portal APIs, and admin APIs, with Render identified as the deployment authority.[4] The schema already has Active Storage, `attorney_profiles`, `cases`, `firm_users`, and `firms`, which means file attachments, attorney metadata, matter-like records, multi-firm linkage, and GHL contact IDs can be reused rather than invented from scratch.[2] Existing docs also document passwordless admin access and strict secret-handling rules: raw secrets must not be committed or pasted, and runtime secrets belong in the production host’s secret store.[5]

| Evidence | Current implication | Build-plan consequence |
| --- | --- | --- |
| `attorney_profiles` has `license_states`, `practice_areas`, `tags`, `source`, `bar_number`, `jurisdiction`, and `years_experience`.[2] | The backend already has a thin attorney profile concept. | Reuse and harden this table for canonical attorney search, but add missing recruiting workflow entities. |
| `cases` has `jurisdiction`, `practice_areas`, `clio_matter_id`, `matter_status`, assignment fields, and `custom_data`.[2] | A matter/case domain was started but is not yet surfaced through APIs. | Treat this as the seed for canonical case records, with careful model/controller cleanup. |
| `firm_users` stores per-firm contact linkage with `contact_id` and `ghl_fund_forge_id`.[2] | The system can map one person to multiple firm/sub-account records. | Use this pattern for Titans Law client sub-account and Titans Law Talent Hub attorney sub-account mappings. |
| Active Storage exists.[2] | The backend can attach generated agreements and can support resumes/matter packets. | Add attachments for resumes, intake files, call transcripts, AI summaries, and staffing artifacts. |
| Current routes lack staffing and Clio endpoints.[3] | The product surface is not yet implemented. | Build new API namespaces and service objects instead of overloading payment/admin endpoints. |
| HighLevel API v1 is end-of-support and v2 uses token/OAuth patterns and rate limits.[6] | New work should avoid legacy API assumptions. | Use v2/private integration or OAuth where available; respect rate limits; centralize connector logic. |
| Clio exposes API surfaces for contacts, matters, relationships, documents, custom fields, tasks, notes, calendars, and webhooks.[7] | Matter setup can be automated. | Build an idempotent Clio sync service around canonical Titans data. |
| Indeed Job Sync is partner/OAuth based and supports job creation, screener questions, status, upsert, and expiration.[8] | Deep Indeed automation is possible but requires partner access. | Start with resume parsing/manual import, then graduate to ATS-style Indeed integration if approved. |

## Required Workflow, End to End

The workflow should begin when the payment system marks a client as paid or otherwise accepted. That event should create or update a canonical `Case` record, attach the source intake materials, run an AI extraction pipeline, create or update a Clio matter, and then open a staffing requirement. The staffing requirement should drive Talent Hub matching first, then Indeed sourcing if no adequate response arrives within the operational threshold.

| Step | Current manual behavior | Automated target behavior |
| --- | --- | --- |
| Client pays | Staff receives GHL notification/task. | Payment success event creates `CaseIntake` and `StaffingRequirement`. |
| Intake collection | Staff downloads call recording and intake form from GHL. | System stores intake form, call recording/transcript, and raw payload as attachments. |
| AI processing | Staff uploads materials to Gemini and asks for Clio case file template. | AI pipeline extracts parties, jurisdiction, case text, case description, risks, recommended practice areas, required licenses, and next tasks. |
| Clio matter setup | Staff creates matter manually, adds parties, budget, stage, relationships, and tasks. | `ClioMatterSyncService` creates/updates contacts, matter, relationships, notes, budget/custom fields, and tasks. |
| Internal matching | Staff filters Talent Hub by licensed state, contact type, practice area, and non-dead stages. | Matching engine filters attorney profiles and existing GHL fields, then produces ranked outreach pools. |
| Outreach | Staff duplicates GHL workflow, writes email/SMS, creates a unique tag, and tags contacts. | System generates opportunity-specific email/SMS drafts, pushes to GHL workflow/tag or sends through Titans communications when available. |
| Candidate response | Attorneys reply or book screener interviews. | System records interest, interview state, and case-specific candidate pipeline status. |
| External sourcing | Staff posts Indeed job if internal response is weak after 24–48 hours. | System generates Indeed-ready job content and screener questions; later posts through Indeed Job Sync when partner integration exists. |
| Resume intake | Staff downloads resumes and creates Talent Hub contacts manually. | Resume parser extracts name, email, phone, bar states, court admissions, practice areas, and experience; then maps to existing GHL custom fields and Titans profile fields. |
| Assignment | Staff/ops selects attorney and starts trial assignment. | `CaseAssignment` records selected attorney, assignment stage, trial status, workload, and restaffing history. |

## Canonical Data Model

The most important implementation principle is that Titans should store **canonical records first** and treat Clio, GHL, and Indeed as connectors. This prevents a second migration problem when Clio and GHL are sunsetted. The existing schema can be extended incrementally, but the implementation should resolve the duplicate `attorneyprofiles` table anomaly before relying heavily on attorney profile migrations.[2]

| Entity | Purpose | Key fields |
| --- | --- | --- |
| `Case` | Canonical legal matter/staffing unit. | `firm_id`, `client_user_id`, `title`, `description`, `jurisdiction`, `county`, `zip_code`, `practice_areas`, `matter_status`, `open_date`, `close_date`, `retainer_amount`, `budget_amount`, `clio_matter_id`, `custom_data`. |
| `CaseIntake` | Raw and AI-processed intake package. | `case_id`, source system, GHL contact/opportunity IDs, intake form attachment, call recording attachment, transcript, AI extraction JSON, confidence, review status. |
| `RelatedParty` | Parties and contacts connected to the case. | `case_id`, name, role, contact info, represented status, counsel info, Clio contact ID. |
| `CaseTask` | AI-generated and staff-created next steps. | `case_id`, title, description, priority, due date, owner, source, Clio task ID, completion status. |
| `StaffingRequirement` | What kind of attorney or staff the case needs. | `case_id`, required state licenses, federal court admissions, practice areas, county/zip, remote/state residency requirement, urgency, target interview count, status. |
| `AttorneyProfile` | Canonical attorney attributes. | Existing profile fields plus residency state, court admissions, tech proficiency, onboarding status, hourly rate, workload target, resume attachment, source. |
| `CandidateApplication` | Indeed or other sourced applicant record. | source, job posting, resume attachment, extracted resume JSON, screening answers, import status, GHL contact ID. |
| `Interview` | Screener/interview workflow. | candidate/attorney, interviewer, stage, scheduled time, notes, decision, no-show/reschedule status. |
| `CaseOpportunity` | Offer of a particular case to a candidate/attorney. | case, attorney/candidate, outreach batch, response, interest state, interview pool state, decline reason. |
| `CaseAssignment` | Actual staffing decision and lifecycle. | case, attorney, role, assigned date, trial flag, workload count, replacement reason, ended date. |
| `ExternalSyncRecord` | Connector-level idempotency and traceability. | local record type/id, provider, external ID, sync status, last payload hash, last error. |
| `FieldMapping` | Existing GHL custom field mapping. | provider, location/sub-account, canonical attribute, external field ID/key, direction, transform, active flag. |

## Existing GoHighLevel Custom Fields

Because the custom fields already exist, the first technical task is **not field creation**. The first task is to inventory and lock the mapping. The system should store a durable mapping table or checked-in configuration that says, for example, “canonical `attorney_profile.license_states` maps to the existing Talent Hub custom field for state licensure,” without exposing secrets or private tokens.

| Mapping area | Existing GHL/Talent Hub concept | Canonical Titans destination |
| --- | --- | --- |
| Attorney identity | First name, last name, email, phone | `users`, `firm_users`, `attorney_profiles` |
| Attorney classification | Contact type = attorney/paralegal/other | `user_type`, `attorney_profiles.tags`, role tables if added |
| Licensure | State licensed in, federal court admissions | `attorney_profiles.license_states`, future `court_admissions` |
| Practice fit | Practice areas, specialties, tags | `attorney_profiles.practice_areas`, `specialties`, `tags` |
| Candidate source | Indeed, referral, database, internal | `attorney_profiles.source`, `candidate_applications.source` |
| Funnel stage | New lead, interview one, interview two, offer, dead, dead waste of time | `candidate_pipeline_stage`, `interviews`, `case_opportunities` |
| Resume | Uploaded file in contact record | Active Storage resume attachment plus GHL file reference |
| Outreach tracking | Workflow tag named after matter/staffing campaign | `outreach_batches`, `case_opportunities`, external GHL tag ID |

The key rule is that **GHL custom fields remain operational fields during the interim phase, not architectural fields**. They should be mapped into the canonical model, and every new automation should write to both systems only through connector services. Future agents should not scatter hard-coded custom field IDs throughout controllers, jobs, or UI components.

## AI Intake and Matter Packet Pipeline

The AI pipeline should be deterministic enough for legal operations. AI should draft and extract, but humans should approve critical legal/matter fields before the Clio sync is treated as final. The pipeline should capture raw source files, the prompt version, model used, extracted JSON, confidence indicators, and a reviewer state.

| AI output | Required fields | Human review requirement |
| --- | --- | --- |
| Case description | Plain-English description, short internal summary, external-safe attorney pitch | Required before outreach if sensitive facts may be included. |
| Jurisdiction recommendation | State, county, federal/state court issue, rationale, confidence | Required before Clio creation and staffing requirement finalization. |
| Related parties | Client, opposing parties, counsel, witnesses, business entities | Required before Clio related contacts are synced. |
| Practice-area recommendation | Broad practice areas and any specialty flags | Required for first launch; later can auto-suggest. |
| Staffing requirement | Required license state, court admission, residency rule, urgency | Required before matching. |
| Next tasks | Investigation tasks, document collection, deadline review, attorney staffing task | Required for legal/process-sensitive tasks. |
| Clio matter template | Matter name, open date, budget, retainer, stage, related contacts, notes | Required before Clio matter sync unless the source is trusted and low risk. |

The existing GHL Call Task Automation repo demonstrates a useful pattern: receive a GHL webhook, extract contact and summary data, send the summary to AI, normalize tasks and due dates, and create tasks back in GHL.[9] The staffing platform should use the same design principle, but it should not leave the canonical result only in GHL. AI results should be persisted in Titans first, then synced outward.

## Clio Matter Creation Design

Clio should be integrated through an idempotent service layer. The service should be able to run repeatedly without duplicate matters, contacts, tasks, or relationships. The current manual workflow treats **open date** as the moment the firm accepts the matter upon client payment, while **close date** is when withdrawal is granted and the file is truly closed.[1] Those definitions should become canonical business rules.

| Clio object | Source in Titans | Sync action |
| --- | --- | --- |
| Contact | Client user and related parties | Find or create contact; update contact details if confidence is high. |
| Matter | Canonical `Case` | Create matter with matter name/number, client, open date, stage, description, budget, and custom fields. |
| Relationships | `RelatedParty` records | Create related contacts and relationship roles. |
| Notes | AI summary and staff review notes | Add internal matter note with AI-generated case description and source trace. |
| Tasks | `CaseTask` records | Create task list for next steps, staffing, document collection, and review deadlines. |
| Documents | Intake attachments, transcripts, generated matter packet | Upload matter packet and supporting files when permitted. |
| Budget/retainer | Payment plan and case financial fields | Set initial budget/retainer, typically using the business-approved retainer amount. |

The implementation should store `clio_matter_id` on `cases`, plus `ExternalSyncRecord` rows for every synced child object. The sync should support dry-run previews for staff, explicit approval, retry with backoff, and clear error reporting when Clio validation fails.

## Attorney Staffing Portal Design

The attorney portal should feel like a modern marketplace rather than an internal CRM clone. Attorneys should manage profile data, licensure, practice areas, court admissions, resume, workload preference, hourly rate expectations, availability, and case-interest settings. Operations staff should manage the supply side with dashboards that show case requirements, match pools, interest responses, interview stages, trial assignments, and restaffing needs.

| Portal surface | Attorney user | Operations/admin user |
| --- | --- | --- |
| Profile | Edit licensure, practice areas, resume, bio, availability, support needs. | Review completeness, verify credentials, flag tech proficiency, set onboarding status. |
| Opportunities | View safe case summaries matched to preferences and licenses. | Create outreach batches, approve summaries, monitor responses. |
| Interest | Mark interested, ask questions, decline with reason. | Move interested candidates into interview pool and compare fit. |
| Interviews | Book screener/second interview, view appointment details. | Add interview notes, move candidate to next stage or rejection/dead stage. |
| Assignments | View assigned matters, expectations, tasks, Clio/Titans links. | Assign trial cases, monitor responsiveness, workload, and restaffing risk. |
| Communications | Receive email/SMS/in-app notifications. | Send bulk outreach without duplicate emails to the same attorney on the same day. |

The meeting notes emphasize several operational rules that should become product behavior rather than tribal knowledge. Staff should first try internal Talent Hub matches, aim to act within 24 hours, escalate to Indeed after weak response in 24–48 hours, avoid “dead waste of time” candidates, and avoid sending multiple separate emails to the same attorney for multiple similar cases in one day.[1] These rules should be encoded into matching, outreach batching, and dashboard warnings.

## Indeed Intake and Resume Parser

Indeed should be handled in two phases. In the short term, the platform should make the manual workflow much faster by allowing staff to upload one or many resumes, parse them, review extracted fields, create/update the attorney contact in GHL Talent Hub, and save the resume in Titans. In the long term, Titans can become an ATS-style integration that posts jobs and receives applicants directly, but this depends on Indeed partner access and OAuth credentials.[8]

| Phase | Capability | Implementation note |
| --- | --- | --- |
| Phase 1 | Resume upload/import assistant | Staff downloads resumes from Indeed and uploads them to Titans; parser extracts identity, license states, court admissions, practice areas, experience, and red flags. |
| Phase 1 | GHL contact sync | Create/update contact in the Talent Hub using existing custom fields and attach or link resume where supported. |
| Phase 1 | Job post generator | AI drafts Indeed job posts from the case staffing requirement, prior templates, required license, practice area, remote status, and screener questions. |
| Phase 2 | Indeed applicant ingestion | Build ATS endpoint for applicant delivery if Indeed Apply/partner approval is obtained. |
| Phase 2 | Job Sync posting | Use Job Sync API to create, upsert, check status, and expire postings with screener questions. |
| Phase 2 | Sponsored/promoted job controls | Track promotion windows, cost policy, and high-value-case approvals separately from ordinary job posting. |

The resume parser should not automatically reject candidates based on age or protected characteristics. It should focus on job-relevant signals such as license state, court admission, legal education, experience, practice areas, work history stability, technology proficiency indicators, location/residency match, and whether the applicant appears to be applying to the correct role. Human reviewers should make final hiring decisions.

## Outreach, Matching, and Case Opportunities

The current GHL workflow duplicates a template, names it after the matter, uses dynamic values, sends email/SMS combinations, and tags matching contacts. The portal should preserve that operating model but make it system-driven. Every outreach should be traceable to a `StaffingRequirement` and `OutreachBatch` so the team can answer who was contacted, what message they received, whether they opened/responded/booked, and why they were or were not selected.

| Matching criterion | Required behavior |
| --- | --- |
| State license | Required match unless the staffing requirement explicitly allows exceptions. |
| Federal court admission | Required when the case is in a specific federal court or when the staffing requirement marks it mandatory. |
| Practice area | Prefer broad practice fit first, then specialty fit for unique areas like bankruptcy, tax, securities, or IP. |
| Residency/location | Prefer or require residence in the case state unless an exception is approved. |
| Funnel stage | Exclude “dead waste of time”; allow revisiting dead/no-answer candidates when appropriate. |
| Prior performance | Rank up responsive, tech-capable, reliable attorneys; rank down poor communication or prior failed trial assignments. |
| Workload | Consider active case count and trial onboarding limits before assigning too many cases. |

The system should support **grouped outreach**. If three Florida civil litigation matters need staffing on the same day, the platform should offer one attorney-facing message summarizing multiple safe opportunities rather than three separate messages. That prevents spam-like behavior and aligns with the meeting instruction to avoid multiple separate emails to the same attorney.[1]

## Implementation Roadmap

The build should be phased so each release improves the current manual process while moving toward the future Titans app. The first releases should avoid broad rewrites and unnecessary dependencies, consistent with the repo-first workflow rules.

| Phase | Goal | Deliverables | Completion gate |
| --- | --- | --- | --- |
| 0 | Field and workflow inventory | Existing GHL custom field map, current Talent Hub stages, Clio custom fields, matter stage definitions, prompt templates, sample cases. | Approved field map stored without secrets. |
| 1 | Canonical case foundation | Harden `Case`, add `CaseIntake`, `RelatedParty`, `CaseTask`, `StaffingRequirement`, `ExternalSyncRecord`, attachments. | Tests cover model validations and idempotent record creation. |
| 2 | AI intake packet | Intake upload, transcript storage, prompt-versioned AI extraction, reviewer UI/API, case summary/task generation. | Staff can review and approve a generated matter packet. |
| 3 | Clio sync | OAuth/credential path, matter/contact/relationship/task/document sync, dry run, retry/error UI. | One test matter can be created idempotently in Clio sandbox or approved environment. |
| 4 | Talent Hub sync | Existing GHL custom field mapping, contact/profile sync, stage sync, tag/workflow connector. | Resume/contact update writes correctly to existing GHL fields. |
| 5 | Staffing dashboard | Case queue, match recommendations, outreach batch creation, attorney response tracking, restaffing queue. | Staff can launch internal outreach from a case without manually duplicating workflows. |
| 6 | Resume parser | Bulk resume upload, structured extraction, review screen, contact create/update, attachment storage. | Staff can import Indeed resumes into Titans/GHL in minutes. |
| 7 | Attorney portal | Attorney login, profile, preferences, opportunities, interest/decline actions, scheduling links. | Attorney can mark interest and ops can see it in staffing dashboard. |
| 8 | Indeed automation | Job post generator first; partner API integration later if approved. | Staff can generate approved job posts; API posting only after credentials/partner access exist. |
| 9 | Titans app cutover | Replace Clio/GHL screens with native matter/staffing/communications surfaces. | New matters and staffing can run without GHL/Clio as primary systems. |

## First Sprint Recommendation

The first sprint should produce the minimum useful automation without waiting for full portal polish. The highest-leverage sprint is: **canonical case intake + AI matter packet + GHL custom-field map + Clio dry-run design**. This gives the team a durable model and reduces the highest-risk manual data-entry step.

| Workstream | Tasks |
| --- | --- |
| Documentation | Add the field mapping inventory template; document matter open/close date definitions; document no-legal-advice and human-review boundaries. |
| Backend | Add/clean canonical case models and attachments; add service skeletons for AI extraction, GHL sync, and Clio sync. |
| AI | Store prompt versions; produce structured JSON for parties, jurisdiction, case description, tasks, and staffing requirements. |
| Ops UI/API | Provide review endpoints/screens for generated matter packet and staffing requirement. |
| Integration | Verify Clio API credential path and GHL v2/private integration approach without committing secrets. |
| Validation | Model tests, service dry-run tests, one end-to-end local seed flow from paid plan to generated case packet. |

## Security, Ethics, and Legal Operations Boundaries

This platform handles confidential legal intake, call recordings, resumes, and sensitive staffing decisions. The build must enforce per-user accounts, least-privilege access, audit logs, and secure attachment handling. Staff-facing tools should include reminders that non-attorney staff must not provide legal advice and that AI-generated legal/matter content requires review before being sent to clients, attorneys, or Clio as final.

Hiring tools should be designed around job-relevant criteria. The system should not encode protected-characteristic screening. It may flag role-relevant operational concerns such as missing bar license, wrong state, lack of legal education for an attorney role, no relevant experience, poor resume completeness, or no evidence of technology capability, but final hiring decisions should remain human-reviewed.

## Risks and Blockers

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| GHL field IDs/names are undocumented | Existing custom fields are built but must be mapped correctly. | Create a field mapping inventory before sync code. |
| Clio/GHL secret handling | Credentials cannot be pasted or committed. | Use approved secret store and environment variables only.[5] |
| Indeed partner access | API posting/applicant ingestion may require partner approval. | Build manual upload/parser first; keep API integration as Phase 2. |
| Duplicate `attorneyprofiles` table | Schema anomaly may cause confusion or migration mistakes. | Investigate and clean with a migration plan before major attorney-profile work.[2] |
| AI hallucination or wrong jurisdiction | Incorrect matter setup can create legal and operational risk. | Require human review for jurisdiction, parties, and staffing requirements. |
| Outreach oversharing | Attorney outreach cannot include excessive sensitive client details. | Generate external-safe summaries and require approval. |
| Over-automation before ops fit is validated | The human workflow is still evolving. | Ship reviewable workflow automation, not irreversible autonomous decisions. |

## Acceptance Criteria for the Completed Build

The platform should be considered successful when a paid client can automatically produce a reviewed matter packet, a Clio matter can be created without duplicate data entry, the relevant staffing requirement can be generated from the case facts, eligible attorneys can be identified through existing Talent Hub fields and canonical attorney profiles, outreach can be sent as a tracked campaign, candidates can express interest or enter interviews, Indeed resumes can be parsed into the Talent Hub and Titans app, and the final attorney assignment can be tracked through trial, active work, and restaffing.

## References

[1]: https://docs.google.com/document/d/1hjQjtTup3DyqtssnWR7TOv68zrwCmX9hDhx12Mg_E3U/edit "May 15, 2026 HR staffing and matter workflow meeting notes provided by the user"
[2]: ../db/schema.rb "Attorney Staffing Portal Backend schema: Active Storage, attorney_profiles, cases, firm_users, firms"
[3]: ../config/routes.rb "Attorney Staffing Portal Backend routes showing current API surface"
[4]: ../README.md "Attorney Staffing Portal Backend README"
[5]: ./admin_auth.md "Fund Forge Admin Authentication and Secret Handling"
[6]: https://help.gohighlevel.com/support/solutions/articles/48001060529-highlevel-api-documentation "HighLevel API Documentation"
[7]: https://docs.developers.clio.com/clio-manage/api-reference/ "Clio Manage API Reference"
[8]: https://docs.indeed.com/job-sync-api/job-sync-api-guide "Indeed Job Sync API guide"
[9]: https://github.com/titanslaw/GHL-Call-Task-Management "GoHighLevel AI Task Automation repository"
