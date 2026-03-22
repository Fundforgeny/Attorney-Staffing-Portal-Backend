# Spreedly iframe vault checkout notes

## Where the iframe vault is hosted

This backend does **not** host the Spreedly iframe itself.

Evidence in the codebase points to a separate frontend/payment origin:

- CORS explicitly allows `https://payments.fundforge.net` and the Render-hosted frontend origins.
- The backend only exposes an `iframe_security` API that returns the certificate token + signed nonce/timestamp payload needed by a browser client.
- The backend stores and processes a `vault_token` after the browser-side iframe tokenizes card data.

## Current checkout/token flow

1. Browser/front-end loads the Spreedly iframe on the payment UI.
2. Browser calls `GET /api/v1/payments/iframe_security` to fetch signing material for secure iframe fields.
3. Browser tokenizes card data with Spreedly and receives a `vault_token`.
4. Browser sends that `vault_token` to backend checkout endpoints such as:
   - `POST /api/v1/payments/checkout`
   - `POST /api/v1/payments/process_payment`
   - `POST /api/v1/payments/3ds/start_checkout`
5. Backend stores a `PaymentMethod` row and then uses the token for purchase / 3DS flows against Spreedly Core.

## What customer data can be fed today

### Accepted directly during checkout creation

`PaymentsController#set_checkout_params` currently accepts:

- `vault_token`
- `card_brand`
- `last4`
- `exp_month`
- `exp_year`
- `cardholder_name`

These are saved when `PaymentService` creates a tokenized payment method.

### Accepted during payment method create/update

`PaymentMethodsController#create` accepts:

- `vault_token`
- `last4`
- `card_brand`
- `exp_month`
- `exp_year`
- `cardholder_name`
- `is_default`

`PaymentMethodsController#update` can push limited customer/billing data to Spreedly:

- `cardholder_name` -> `full_name`
- `billing_email` -> `email`
- `billing_zip` -> `zip`
- `metadata` -> `metadata`

That update is performed by `Spreedly::PaymentMethodsService#update_payment_method`.

## What is not currently fed in the checkout token/process

The current checkout/token endpoints do **not** accept or persist full billing/contact data such as:

- full street address
- city/state/postal/country as structured fields
- phone number
- email during checkout tokenization

The only customer identity automatically inferred at checkout is the cardholder name fallback from the user record.

## Practical implication

If you want to feed **full address, name, phone, email, etc.** as part of the checkout process, the current backend supports only part of that:

- **Name**: supported (`cardholder_name` / `full_name`)
- **Email**: supported only through payment method update, not initial checkout
- **ZIP**: supported only through payment method update, not initial checkout
- **Phone**: not wired
- **Full address**: not wired

## Recommended implementation path

1. Capture the customer/contact fields on the frontend that hosts the Spreedly iframe.
2. After tokenization, either:
   - extend `payment_methods#create` / `payment_methods#update`, or
   - extend `payments/checkout` and `payments/3ds/start_checkout`
   so they accept billing/contact fields.
3. Expand `Spreedly::PaymentMethodsService#update_payment_method` to pass any additional Spreedly-supported fields/metadata.
4. If Spreedly does not support all desired fields as first-class payment-method attributes, send them in `metadata` and/or persist them locally on your own models.

## Likely hosting answer

Based on the allowed origins, the most likely live host for the Spreedly iframe experience is `https://payments.fundforge.net`, with local development support from `http://localhost:5173` / `http://127.0.0.1:5173`.
