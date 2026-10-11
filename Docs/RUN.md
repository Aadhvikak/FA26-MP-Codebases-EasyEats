# Running EasyEats locally

EasyEats recommends UIUC dining-hall meals based on your nutrition goals and tracks what
you eat. It's a Flutter app backed by a small Express API, a SQLite menu database and a
Python meal planner.

## Prerequisites

- Node.js 20+
- Python **3.12** (see `.python-version`)
- Flutter **3.35+** (Dart `^3.9.2`), plus a run target: Linux/macOS/Windows desktop,
  Chrome, or an Android/iOS emulator
- No API keys or accounts needed

## 1. Backend (port 3000)

```bash
python3.12 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r Backend/scrapers/requirements.txt

cd Backend
npm ci
node server.js                     # or: npm run dev (auto-restart)
```

Keep the venv **activated** in this terminal: `server.js` spawns `python3`
(`meal-planning/meal_planner.py`) for `/api/meal-plan`, and that needs pandas/numpy.

Check it's up: `curl localhost:3000/health`. Port can be changed with `PORT=3001`.

## 2. Flutter app

```bash
cd Frontend/flutter_easyeats
flutter pub get
flutter run -d linux               # or: -d chrome, -d macos, -d windows, or an emulator
```

The API base URL is hard-coded to `http://localhost:3000` in
`lib/services/auth_service.dart`, `lib/services/nutrition_service.dart`,
`lib/pages/change_password_page.dart` and `lib/pages/dining1_ike.dart`.
On an **Android emulator** change it to `http://10.0.2.2:3000`; on a physical phone use
your computer's LAN IP.

## Data

| File | Contents |
|---|---|
| `Backend/data/nutrition_data.db` | SQLite menu + nutrition data (table `nutrition_data`) |
| `Backend/data/users.json` | User accounts (PBKDF2-hashed passwords) and profiles |
| `Backend/data/meal_tracking.json` | Logged meals |

The menu DB was loaded from `complete_dining_data_20251204_070010.xlsx`, a December 2025
scrape. It covers 5 dining halls, but not every hall has every meal
(for example, there is no Ikenberry dinner data).

To refresh menus:

```bash
cd Backend/scrapers
python nutrition_scraper.py        # Selenium; needs Google Chrome installed
python load_to_db.py <output>.xlsx # replaces the contents of ../data/nutrition_data.db
```

## Code map

```
Backend/
  server.js               Express API (routes listed in Docs/API_HANDBOOK.md)
  auth.js                 file-based user store + password hashing
  meal-planning/          Python meal planner called by /api/meal-plan
  scrapers/               dining-site scraper + Excel -> SQLite loader
Frontend/flutter_easyeats/lib/
  pages/  services/  models/
WebScraping/, Research/   earlier experiments
*.xlsx, *.csv (root)      raw scrape exports
```

API reference: [`API_HANDBOOK.md`](API_HANDBOOK.md).
