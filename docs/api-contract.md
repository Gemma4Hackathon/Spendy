# Spendy – API Contract

Base URL (dev): `http://localhost:8000/api/v1`  
All requests: `Content-Type: application/json`

---

## POST /spending/summary

Generate a finance summary from spending entries.

### Request
```json
{
  "entries": [
    {
      "title": "珍珠奶茶",
      "amount": 85,
      "category": "beverages",
      "date": "2026-04-26T14:00:00Z",
      "note": ""
    }
  ]
}
```

### Response
```json
{
  "total_spent": 3240.0,
  "top_category": "foodDelivery",
  "risk_categories": ["beverages", "foodDelivery", "lateNight"],
  "ai_message": "過去 30 天...",
  "category_breakdown": {
    "beverages": 645.0,
    "foodDelivery": 1450.0,
    "lateNight": 335.0
  }
}
```

---

## POST /health/scan

Extract health metrics from an uploaded image.

### Request
```
Content-Type: multipart/form-data
file: <image binary>
```

### Response
```json
{
  "metrics": [
    {
      "name": "空腹血糖",
      "value": "112",
      "unit": "mg/dL",
      "normal_range": "< 100",
      "status": "borderline",
      "icon": "drop.fill",
      "progress": 0.74
    }
  ],
  "report_date": "2026-03-26",
  "lab_name": "台大醫院健檢中心"
}
```

Status values: `"normal"` | `"borderline"` | `"warning"`

---

## POST /insights/generate

Generate cross-domain insights from profile + spending + health data.

### Request
```json
{
  "profile": {
    "name": "Alex Chen",
    "age": 28,
    "gender": "男",
    "height_cm": 175,
    "weight_kg": 79.2,
    "goals": ["控制血糖"],
    "lifestyle": "久坐辦公室"
  },
  "spending_entries": [ ... ],
  "health_report": { ... }
}
```

### Response
```json
{
  "key_findings": [
    {
      "icon": "🧋",
      "cause": "高糖飲品消費",
      "cause_detail": "過去 30 天花費 NT$645...",
      "health_impact": "血糖偏高",
      "health_detail": "空腹血糖 112 mg/dL...",
      "risk": "若持續 6 個月...",
      "accent_color": "amber",
      "actions": [
        {
          "title": "改成無糖或微糖",
          "description": "每杯少加糖可減少 200–400 kcal",
          "expected_outcome": "3 個月後血糖可降至正常",
          "timeframe": "3 個月",
          "difficulty": 2
        }
      ]
    }
  ],
  "overall_risk_score": 68,
  "monthly_spending_at_risk": 3200.0,
  "generated_at": "2026-04-26T14:00:00Z"
}
```

---

## GET /demo/{scenario}

Load a pre-built demo scenario.

### Scenarios
| scenario | description |
|---|---|
| `full` | 綜合情境（手搖飲 + 外送 + 夜生活） |
| `sugar` | 高糖飲品 × 血糖風險 |
| `night` | 深夜外送 × 代謝異常 |
| `caffeine` | 咖啡因依賴 × 睡眠障礙 |

### Response
```json
{
  "profile": { ... },
  "spending_entries": [ ... ],
  "health_report": { ... },
  "insight_result": { ... }
}
```

---

## Error Format (all endpoints)
```json
{
  "error": "parse_error",
  "message": "無法解析健檢圖片，請確認圖片清晰度"
}
```
