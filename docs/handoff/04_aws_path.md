# AWS Path

## Goal

Keep a clear plan for moving beyond Firebase if scale, cost, moderation, regional controls, or vendor flexibility require a stronger custom backend path.

## Recommended AWS mapping for this project

Suggested service mapping:

- Auth: Amazon Cognito user pools or a custom auth broker
- Data API: AWS AppSync or API Gateway plus Lambda
- Realtime events: AppSync subscriptions, AppSync Events, or a custom event pipeline
- Media storage: Amazon S3
- Media delivery: CloudFront
- Push fanout: Amazon SNS using APNs and FCM credentials
- Secrets and config: AWS Secrets Manager or SSM Parameter Store
- Key management: AWS KMS
- Edge protection: AWS WAF

## Why this project can support that path

The Flutter app already avoids backend-specific SDK use in presentation code.

That matters because:

- repositories can swap from local to Firebase to AWS
- push delivery is behind a service seam
- media transfer is behind a service seam
- call provider selection is already modeled as a boundary

## Recommended AWS adoption order

### Step 1: auth

If Firebase Auth is not enough, map `AuthRepository` to Cognito or a custom auth broker.

What Cognito is good at:

- user directory
- app authentication
- token issuance
- federation
- challenge-based flows

### Step 2: app data

Two main options:

1. AppSync
2. API Gateway plus Lambda

Use AppSync if:

- you want GraphQL
- you need efficient real-time updates
- you want mobile-friendly data sync patterns

Use API Gateway plus Lambda if:

- you want a more explicit REST or custom API design
- you want tighter backend orchestration
- moderation and custom business logic are heavy

### Step 3: media

Map `MediaTransferService` and future media repositories to:

- S3 for storage
- CloudFront for delivery
- signed URLs or controlled upload flows

### Step 4: push

Map push registration and delivery to:

- APNs and FCM credentials
- SNS for mobile push fanout
- your own server-side endpoint management and token lifecycle

### Step 5: moderation and abuse controls

Add server-side controls before public release:

- rate limiting
- message abuse controls
- audit logging
- moderation tooling
- suspicious activity monitoring

## When to choose AWS over Firebase

Strong reasons to escalate:

- Firestore cost or indexing limits become painful
- custom moderation needs become significant
- you need more explicit API control
- you want stronger vendor independence
- you need more custom event processing or compliance controls

## Mixed-provider option

You do not need to move everything at once.

A practical mixed path could be:

- Firebase Auth initially
- AWS data APIs later
- S3 for media later
- external call provider for calling
- dedicated moderation services on AWS

The current app architecture supports this style better than a monolithic provider rewrite.

## Suggested AWS-first implementation plan if Firebase is skipped

1. Define the auth strategy
2. Define the data schema and API surface
3. Implement live repositories one feature at a time
4. Keep the local fallback path alive until each AWS-backed adapter is stable
5. Add push fanout only after APNs and FCM server-side credentials are ready
6. Add real call signaling only after deciding the transport provider

## Official docs to verify on the new machine

- Amplify Flutter:
  - https://docs.amplify.aws/flutter/
- Amplify Flutter auth setup:
  - https://docs.amplify.aws/flutter/build-a-backend/auth/set-up-auth/
- Connect Amplify Flutter to existing resources:
  - https://docs.amplify.aws/flutter/frontend/connect-to-existing-resources/
- Amazon Cognito user pools:
  - https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools.html
- AWS AppSync:
  - https://docs.aws.amazon.com/appsync/latest/devguide/what-is-appsync
- Amazon SNS mobile push:
  - https://docs.aws.amazon.com/sns/latest/dg/mobile-push-wns.html

## What not to do

- do not wire AWS SDK logic directly into Flutter presentation code
- do not implement push delivery without APNs and FCM prerequisites
- do not start with a full backend rewrite if Firebase dev validation has not happened yet
- do not mix production infrastructure with temporary development credentials
