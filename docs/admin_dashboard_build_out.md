# Admin Dashboard Backend Build-Out Status

Last updated from ChatGPT conversation review.

## Deployment authority

- Backend deploy branch: `main`.
- Backend deploy target: Render, as documented in `docs/render_deployment.md`.
- Frontend deploys separately from the frontend repository `staging` branch.

## What is actually built in backend code

### Admin auth and dashboard API

- Admin dashboard API endpoint exists at `GET /api/v1/admin/dashboard`.
- Controller file: `app/controllers/api/v1/admin/dashboard_controller.rb`.
- The controller now delegates live business/risk metric calculation to `AdminDashboardMetricsService`.
- Service file: `app/services/admin_dashboard_metrics_service.rb`.

### Client and transaction search

- Admin user/client search endpoint exists at `GET /api/v1/admin/users?q=...`.
- Controller file: `app/controllers/api/v1/admin/users_controller.rb`.
- Search is intended to support client name, email, phone, plan name, checkout session ID, payment transaction ID, refund transaction ID, decline reason, card brand/last4, payment amount, refunded amount, plan amounts, and dates.
- `GET /api/v1/admin/users/:id` returns client profile data with plans, payment methods, and payment history.

### Refund API

- Admin refund endpoint exists at `POST /api/v1/admin/payments/:id/refund`.
- Controller file: `app/controllers/api/v1/admin/payments_controller.rb`.
- Refund action uses `Admin::PaymentRefundService`.
- Payment responses include refund-oriented fields such as `refundable_amount`, `refunded_amount`, `refund_transaction_id`, `refunded_at`, and `last_refund_reason`.

### Payment date filtering

- Admin payments index supports `from` and `to` date filters.
- Date filtering should use transaction-date fallback logic: `paid_at`, then `scheduled_at`, then `created_at`.
- This supports the frontend Last 30 Days of Payments button.

### Chargeflow alert/dispute fields

Chargeflow fields exist on `payments` through migration `db/migrate/20260423100000_add_chargeflow_fields_to_payments_and_plans.rb`:

- `payments.disputed`
- `payments.chargeflow_alert_id`
- `payments.chargeflow_dispute_id`
- `payments.disputed_at`
- `payments.chargeflow_recovery`
- `plans.chargeflow_alert_fee`

These fields are the current source for dashboard alert/dispute metrics.

## Business metrics intended for dashboard

The dashboard should prioritize operating risk and cash-reserve decisions, not raw activity counts.

Required live metrics:

- Revenue over the current 30 days.
- Revenue over the prior 30 days.
- 30-day revenue trend/change percentage.
- 120-day revenue base.
- 120-day returned amount.
- 120-day return exposure as a dollar percentage of collected revenue.
- Estimated reserve needed against current 30-day revenue.
- Estimated amount to set aside per `$10,000` collected.
- Voluntary refunds amount.
- Alert amount/count.
- Dispute/chargeback amount/count.
- Current active payment-plan count.
- Overdue active payment-plan count.
- Plan default rate: overdue active plans divided by active plans.
- Prior 30-day default rate and trend.

## Important business definition

The return rate that matters is not raw count of failed payments.

Return exposure should answer:

> If Fund Forge collects `$10,000`, based on the prior 120 days, how much statistically needs to be reserved because money comes back through voluntary refunds, alerts resolved by refund, or disputes/chargebacks?

Formula intent:

```text
return_amount_rate_percent = (voluntary_refunds + alert_refund_exposure + dispute_exposure) / successful_collected_revenue * 100
estimated_reserve_needed = current_30_day_revenue * return_amount_rate_percent / 100
estimated_return_per_10000_collected = 10000 * return_amount_rate_percent / 100
```

## Known gaps / VM next steps

1. Verify `AdminDashboardMetricsService` works in Rails boot/autoload in the deployed environment.
2. Run backend tests or at least Rails console smoke checks against:
   - `GET /api/v1/admin/dashboard`
   - `GET /api/v1/admin/users?q=<known client/email/phone/transaction>`
   - `GET /api/v1/admin/payments?from=<date>&to=<date>`
3. Confirm payment date filtering in `Api::V1::Admin::PaymentsController#index` uses transaction-date fallback, not only `scheduled_at`.
4. Confirm return exposure does not double-count the same payment when it has both an alert and dispute marker.
5. Confirm `refunded_amount` is populated for voluntary refunds and not just gateway metadata.
6. Confirm dashboard metrics use the business-approved statuses for active and overdue payment plans.
7. Do not replace code wholesale when patching. Prefer service objects/components and small controller/view insertions.
8. Do not commit secrets. Use Render environment variables, GitHub Actions secrets, or provider consoles.

## One-command backend smoke check suggestion

Run this from the deployed backend environment or Rails console host:

```bash
bundle exec rails runner 'puts AdminDashboardMetricsService.new.call.to_json'
```

If it fails, fix backend metrics before changing frontend UI.
