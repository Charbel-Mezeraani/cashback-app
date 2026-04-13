# 💰 Cashback App

A full-stack cashback rewards platform that lets users scan product barcodes in-store, submit receipts, and earn cashback directly to their in-app wallet.

---

## Overview

| Layer | Technology | Hosting |
|-------|-----------|---------|
| Mobile | Flutter (Android & iOS) | APK / App Store |
| Backend API | Node.js + Express | Railway |
| Database | PostgreSQL | Railway |
| Admin Dashboard | HTML/Alpine.js + Next.js | Railway |

---

## Features

### Mobile App (Flutter)
- **Barcode Scanner** — scan any product barcode to check active cashback offers
- **Receipt Submission** — photo receipt upload with fraud scoring
- **Wallet** — real-time cashback balance, transaction history, payout requests
- **Claim History** — track approved, pending, and rejected claims
- **Onboarding** — smooth first-launch flow with auth
- **Secure Auth** — JWT access tokens + refresh tokens stored in secure storage

### Backend API (Node.js / Express)
- RESTful API with JWT authentication and rate limiting
- Rule-based fraud detection on every receipt submission
- Receipt OCR pipeline with image upload (Multer + S3-compatible storage)
- Real-time wallet transaction management
- Push notification support
- Admin-only analytics, campaign management, and claims review endpoints
- Structured logging via Winston with daily log rotation
- Helmet security headers + CORS

### Admin Dashboard
- Live analytics: claims, cashback paid, cost per acquisition, active campaigns
- Claims review queue with one-click approve/reject
- Product management with image upload and automatic campaign creation
- Campaign creation and management
- **AI Insights** — rule-based intelligence engine that detects:
  - Low-conversion campaigns
  - Weekend purchase pattern peaks
  - Retention rate drops
  - Week-over-week growth/decline alerts
  - Fraud flag rate spikes
- Data monetisation tiers and on-demand report catalogue

---

## Project Structure

```
cashback-app/
├── mobile/              # Flutter app
│   └── lib/
│       ├── core/        # API client, auth, config
│       ├── features/    # auth, scan, claim, wallet, home, history, account
│       └── shared/      # widgets, theme
│
├── backend/             # Node.js/Express API
│   └── src/
│       ├── config/      # DB, logger, S3
│       ├── middleware/  # auth, adminAuth, rateLimit, requestLogger, validate
│       ├── routes/      # auth, products, receipts, claims, wallet, notifications
│       │   └── admin/   # analytics, campaigns, claims, products, auth
│       └── public/
│           └── admin/   # Static admin dashboard (Alpine.js)
│
└── admin/               # Next.js admin dashboard (advanced analytics)
    └── app/
        ├── page.tsx         # Overview with charts
        ├── campaigns/       # Campaign performance
        ├── products/        # Product management
        ├── users/           # User segments
        └── insights/        # AI Insights + data monetisation
```

---

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.10
- Node.js ≥ 18
- PostgreSQL 14+

### Backend

```bash
cd backend
cp .env.example .env          # fill in DATABASE_URL, JWT_SECRET, etc.
npm install
npm run migrate               # run DB migrations
npm run dev                   # starts on port 3000
```

**Environment variables:**

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | Secret for signing access tokens |
| `JWT_REFRESH_SECRET` | Secret for refresh tokens |
| `CORS_ORIGINS` | Comma-separated allowed origins |
| `AWS_*` / `S3_*` | S3-compatible storage for receipt images |

### Mobile App

```bash
cd mobile
flutter pub get
flutter run                   # requires a connected device or emulator
```

Update `lib/core/api/api_client.dart` with your backend URL before building.

### Admin Dashboard (static)

Served automatically at `/admin` by the backend. No separate setup needed.

### Admin Dashboard (Next.js)

```bash
cd admin
npm install
npm run dev                   # starts on port 3001
```

Set `NEXT_PUBLIC_API_URL` to your backend URL.

---

## API Overview

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/auth/register` | Register new user |
| `POST` | `/auth/login` | Login, returns JWT pair |
| `POST` | `/auth/refresh` | Refresh access token |
| `GET` | `/products/:barcode` | Lookup product + active campaign |
| `GET` | `/products/campaigns/active` | All active cashback campaigns |
| `POST` | `/receipts` | Submit receipt for a claim |
| `GET` | `/claims` | User's claim history |
| `GET` | `/wallet` | Wallet balance + transactions |
| `POST` | `/wallet/payout` | Request a payout |
| `GET` | `/notifications` | User notifications |

**Admin endpoints** (`/admin/*`) require an admin JWT:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/admin/auth/login` | Admin login |
| `GET` | `/admin/analytics` | Dashboard summary |
| `GET` | `/admin/analytics/insights` | AI-generated insights |
| `GET` | `/admin/claims` | All claims with filters |
| `POST` | `/admin/claims/:id/approve` | Approve a flagged claim |
| `POST` | `/admin/claims/:id/reject` | Reject a claim |
| `GET` | `/admin/campaigns` | List campaigns |
| `POST` | `/admin/campaigns` | Create campaign |
| `GET` | `/admin/products` | List products |
| `POST` | `/admin/products` | Create product + campaign |

---

## Deployment

The app is deployed on [Railway](https://railway.app):

- **`fearless-freedom`** — Backend API + static admin dashboard
- **`accurate-empathy`** — Next.js advanced admin dashboard
- **Postgres** — Managed PostgreSQL instance

Deployments are triggered via `railway up` from the respective directories.

---

## Tech Stack

**Mobile:** Flutter · Riverpod · GoRouter · Dio · MobileScanner · flutter_secure_storage

**Backend:** Node.js · Express · PostgreSQL · JWT · Multer · Winston · Helmet · Bull · Redis · Sharp · AWS S3

**Admin:** Alpine.js · Tailwind CSS · Next.js 16 · Recharts · TypeScript

---

## License

Private — all rights reserved.
