# Spendy – iOS Architecture

## Overview

Spendy is a mobile-first, privacy-aware personal health + finance intelligence app built on Gemma 4.  
It cross-correlates daily spending behavior with health check data to produce actionable, explainable insights.

---

## Tech Stack

| Layer | Technology |
|---|---|
| iOS Frontend | SwiftUI (iOS 17+), Swift 5.9+ |
| State Management | `@Observable` / `@Environment` (iOS 17 native) |
| Backend | FastAPI (Python 3.9+) |
| AI Model | Gemma 4 (on-device via LiteRT / Cactus routing) |
| On-device Inference | LiteRT (Google AI Edge) |
| Mobile AI Router | Cactus (local-first routing) |
| Model Training | Unsloth fine-tune on medical QA |
| Model Hub | Hugging Face (external asset) |

---

## Monorepo Structure

```
Spendy/
├── ios/                    # SwiftUI app (this document)
│   └── Spendy/
│       └── Spendy/
│           ├── App/        # AppState, MainTabView
│           ├── Features/   # Screen-level views (feature slices)
│           ├── Models/     # Data models
│           ├── Services/   # API protocol + mock
│           └── Shared/     # Theme, reusable components
├── backend/                # FastAPI (to be built by teammate)
├── engine/                 # Inference engine (LiteRT / Cactus integration)
├── docs/                   # This file and other docs
└── contracts/              # OpenAPI schema
```

---

## iOS Screen Architecture

```
SpendyApp
└── MainTabView (TabView, 5 tabs)
    ├── Tab 0: ProfileView
    ├── Tab 1: SpendingView → AddSpendingView (sheet)
    ├── Tab 2: FinanceAssistantView
    ├── Tab 3: HealthScanView → HealthResultsView → InsightsView (push)
    └── Tab 4: InsightsView (direct access)
```

### State Flow
```
AppState (@Observable, injected via .environment)
    ├── profile: UserProfile
    ├── spendingEntries: [SpendingEntry]
    ├── healthReport: HealthReport?
    ├── insightResult: InsightResult?
    └── selectedTab: Int (for cross-tab navigation)
```

---

## AI / Model Architecture

### Routing Logic (Cactus)

```
User Action (iOS)
    ↓
CactusRouter.route(task)
    ├── Simple / Privacy-sensitive → LiteRT on-device (Gemma 4 quantized)
    └── Complex / Network available → FastAPI → Full Gemma 4
```

### On-device Capabilities (LiteRT)
- Spending category classification
- Health metric anomaly detection
- Simple insight generation

### Server-side Capabilities (FastAPI)
- OCR / multimodal health report extraction
- Full cross-domain reasoning
- Fine-tuned medical knowledge QA (Unsloth model)

---

## API Flow (Current: Mock)

```
iOS                         FastAPI
 │                              │
 │──POST /api/v1/spending/summary──▶│
 │◀──── FinanceSummary ────────────│
 │                              │
 │──POST /api/v1/health/scan ──▶│
 │◀──── HealthReport ──────────│
 │                              │
 │──POST /api/v1/insights/generate▶│
 │◀──── InsightResult ─────────│
```

---

## Privacy by Design

- All sensitive data stored on-device (SwiftData / UserDefaults)
- On-device inference preferred via LiteRT + Cactus routing
- No health data transmitted without explicit user consent
- Backend calls use end-to-end encrypted connections
