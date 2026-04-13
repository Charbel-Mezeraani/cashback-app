<div align="center">

# Cashback App

**A full-stack cashback rewards platform — scan, claim, earn.**

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-18+-339933?logo=nodedotjs&logoColor=white)](https://nodejs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14+-4169E1?logo=postgresql&logoColor=white)](https://postgresql.org)
[![Railway](https://img.shields.io/badge/Deployed_on-Railway-0B0D0E?logo=railway&logoColor=white)](https://railway.app)

</div>

---

## What It Does

Users install the mobile app, scan a product barcode in-store, photograph their receipt, and receive cashback directly to their in-app wallet. Brands run targeted campaigns to drive purchase behaviour. An admin dashboard gives operators full visibility and control.

---

## Architecture

```
┌─────────────────────┐        HTTPS         ┌──────────────────────────┐
│   Flutter Mobile    │ ──────────────────▶  │   Node.js / Express API  │
│  Android · iOS      │                       │      Railway             │
└─────────────────────┘                       └────────────┬─────────────┘
                                                           │
                                              ┌────────────▼─────────────┐
                                              │  PostgreSQL Database      │
                                              │      Railway             │
                                              └──────────────────────────┘
                                                           │
                                              ┌────────────▼─────────────┐
                                              │   Admin Dashboard         │
                                              │  Alpine.js · Next.js     │
                                              └──────────────────────────┘
```

| Layer | Stack | Hosting |
|---|---|---|
| Mobile | Flutter 3, Riverpod, GoRouter, MobileScanner | APK / App Store |
| API | Node.js, Express, JWT, PostgreSQL | Railway |
| Admin (static) | Alpine.js, Tailwind CSS | Railway (served by API) |
| Admin (advanced) | Next.js 16, TypeScript, Recharts | Railway |
| Database | PostgreSQL 14 | Railway Managed |

---

## Features

### Mobile App

- **Barcode scanner** — instant product lookup and cashback eligibility check
- **Receipt submission** — photo upload with server-side fraud scoring
- **In-app wallet** — real-time balance, transaction ledger, payout requests
- **Claim history** — full audit trail with status tracking
- **Secure authentication** — JWT access + refresh tokens in encrypted storage
- **Smooth onboarding** — first-launch flow with profile setup

### Backend API

- RESTful architecture with versioned routes
- **Fraud detection engine** — scores every receipt submission automatically
- **Image pipeline** — Multer upload → Sharp processing → S3 storage
- **Rate limiting** — per-IP and per-user limits via Redis
- **Request tracing** — UUID per request, structured Winston logging, daily rotation
- **Security** — Helmet CSP headers, CORS whitelist, bcrypt password hashing
- Background job queue with Bull for async receipt processing

### Admin Dashboard

- Live KPIs: total claims, cashback paid, cost per acquisition, active campaigns
- Claims review queue — approve or reject flagged submissions in one click
- Product management — add products with image upload, auto-creates campaign
- Campaign builder — fixed or percentage cashback, date ranges, claim caps
- **AI Insights engine** — rule-based intelligence that surfaces:
  - Low-conversion campaign warnings
  - Weekend purchase pattern detection
  - Retention rate drops below threshold
  - Week-over-week growth and decline alerts
  - Fraud flag rate spikes
- **Data monetisation catalogue** — tiered pricing for anonymised purchase data (Starter $299/mo · Professional $799/mo · Enterprise custom)
- On-demand report marketplace

---

## Project Structure

```
cashback-app/
│
├── mobile/                        # Flutter application
│   └── lib/
│       ├── core/                  # API client, auth state, config
│       ├── features/
│       │   ├── auth/              # Login, register, onboarding
│       │   ├── scan/              # Barcode scanner screen
│       │   ├── claim/             # Receipt upload & claim flow
│       │   ├── wallet/            # Balance, transactions, payouts
│       │   ├── history/           # Claim history
│       │   ├── home/              # Dashboard feed
│       │   └── account/           # Profile settings
│       └── shared/                # Reusable widgets, theme
│
├── backend/                       # Node.js / Express API
│   ├── migrations/                # Versioned SQL migrations (010 files)
│   └── src/
│       ├── config/                # Database, logger, S3 clients
│       ├── middleware/            # auth, adminAuth, rateLimit, validate, logger
│       ├── routes/
│       │   ├── auth.js            # Register, login, refresh, me
│       │   ├── products.js        # Barcode lookup, active campaigns
│       │   ├── receipts.js        # Receipt submission & OCR pipeline
│       │   ├── claims.js          # Claim status & history
│       │   ├── wallet.js          # Balance, transactions, payouts
│       │   ├── notifications.js   # Push notifications
│       │   └── admin/
│       │       ├── analytics.js   # Dashboard KPIs + AI insights
│       │       ├── campaigns.js   # Campaign CRUD
│       │       ├── claims.js      # Claims review queue
│       │       ├── products.js    # Product management
│       │       └── auth.js        # Admin authentication
│       ├── jobs/                  # Bull queue workers
│       └── public/admin/          # Static admin dashboard
│
└── admin/                         # Next.js advanced analytics
    └── app/
        ├── page.tsx               # Overview — KPIs, charts, heatmap
        ├── campaigns/             # Campaign performance table
        ├── products/              # Product management + image upload
        ├── users/                 # User segments
        └── insights/              # AI insights + data monetisation
```

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.10
- Node.js ≥ 18
- PostgreSQL 14+
- Redis (for rate limiting and job queue)

### Backend

```bash
cd backend
cp .env.example .env      # fill in the variables below
npm install
npm run migrate           # applies all SQL migrations
npm run dev               # http://localhost:3000
```

**Required environment variables:**

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | Secret key for access tokens |
| `JWT_REFRESH_SECRET` | Secret key for refresh tokens |
| `REDIS_URL` | Redis connection string |
| `CORS_ORIGINS` | Comma-separated allowed frontend origins |
| `AWS_ACCESS_KEY_ID` | S3-compatible storage key |
| `AWS_SECRET_ACCESS_KEY` | S3-compatible storage secret |
| `S3_BUCKET` | Bucket name for receipt images |
| `S3_ENDPOINT` | S3 endpoint URL |

### Mobile App

```bash
cd mobile
flutter pub get
flutter run               # requires connected device or running emulator
```

Update `lib/core/api/api_client.dart` with your backend base URL before building for production.

### Static Admin Dashboard

Automatically served at `/admin` by the backend — no separate setup required.

### Next.js Admin Dashboard

```bash
cd admin
npm install
npm run dev               # http://localhost:3001
```

| Variable | Description |
|---|---|
| `NEXT_PUBLIC_API_URL` | Backend base URL |
| `NEXT_PUBLIC_ADMIN_KEY` | Admin API key |

---

## API Reference

### User Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/auth/register` | Create account |
| `POST` | `/auth/login` | Authenticate, receive JWT pair |
| `POST` | `/auth/refresh` | Rotate access token |
| `GET` | `/auth/me` | Current user profile |
| `GET` | `/products/:barcode` | Lookup product + active campaign |
| `GET` | `/products/campaigns/active` | All live cashback offers |
| `POST` | `/receipts` | Submit receipt for a claim |
| `GET` | `/claims` | User's claim history |
| `GET` | `/wallet` | Balance and transactions |
| `POST` | `/wallet/payout` | Request cashback payout |
| `GET` | `/notifications` | User notifications |

### Admin Endpoints

> All `/admin/*` routes require a valid admin JWT (`Authorization: Bearer <token>`).

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/admin/auth/login` | Admin authentication |
| `GET` | `/admin/analytics` | Full dashboard summary |
| `GET` | `/admin/analytics/insights` | AI-generated business insights |
| `GET` | `/admin/claims` | Paginated claims with filters |
| `POST` | `/admin/claims/:id/approve` | Approve a flagged claim |
| `POST` | `/admin/claims/:id/reject` | Reject a claim |
| `GET` | `/admin/campaigns` | List all campaigns |
| `POST` | `/admin/campaigns` | Create a new campaign |
| `GET` | `/admin/products` | List all products |
| `POST` | `/admin/products` | Create product + campaign (multipart) |

---

## Deployment

Deployed on [Railway](https://railway.app) with two services and a managed database:

| Service | Description |
|---|---|
| `fearless-freedom` | Backend API + static admin dashboard |
| `accurate-empathy` | Next.js advanced analytics |
| `Postgres` | Managed PostgreSQL instance |

Continuous deployment via `railway up` from each service directory.

---

## Tech Stack

**Mobile**
Flutter · Dart · Riverpod · GoRouter · Dio · MobileScanner · flutter_secure_storage · Shimmer · Cached Network Image

**Backend**
Node.js · Express · PostgreSQL · JWT · Multer · Sharp · AWS S3 SDK · Bull · Redis · Winston · Helmet · bcryptjs · UUID

**Admin**
Alpine.js · Tailwind CSS · Next.js 16 · TypeScript · Recharts · date-fns · Axios

**Infrastructure**
Railway · Docker · Nixpacks · PostgreSQL 14

---

## Screenshots

> Coming soon — mobile app walkthrough, admin dashboard, AI insights panel.

---

## License

Private — all rights reserved © 2026
