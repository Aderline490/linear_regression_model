# Africa Education Access Predictor

## Mission & Problem
Our mission is to empower and uplift children in orphanages across Africa by expanding
educational opportunity, emotional support and long-term self-reliance, connecting them
with reliable families so every child can grow with dignity and hope. This project predicts
the **percentage of primary-school-age children who are out of school** in a given African
country-year, from socioeconomic, health and demographic indicators — so that education and
family-support programs can be targeted at the strongest drivers of exclusion.

## Dataset
Built from the **[World Bank Open Data API](https://data.worldbank.org)** (public, no API key
required) — see [`summative/linear_regression/data/build_dataset.py`](summative/linear_regression/data/build_dataset.py).
It pulls real official indicators (GDP per capita, government education spending, under-5
mortality, rurality, health spending, internet access, unemployment, life expectancy,
population) for **all 54 African countries, 2000–2022**, and merges them into
[`africa_out_of_school.csv`](summative/linear_regression/data/africa_out_of_school.csv)
(708 rows × 14 columns). This is a real multi-country panel dataset assembled specifically
for this mission — not the house-price dataset covered in class.

## Live API
- **Swagger UI (interactive docs):** `<PASTE_YOUR_RENDER_URL_HERE>/docs`
- **Predict endpoint:** `POST <PASTE_YOUR_RENDER_URL_HERE>/predict`
- **Retrain endpoint:** `POST <PASTE_YOUR_RENDER_URL_HERE>/retrain` (multipart CSV upload)

> Deploy `summative/API` to [Render](https://render.com) (see below) and paste the resulting
> public URL above and in `summative/FlutterApp/lib/main.dart` (`kApiBaseUrl`).

## Video Demo
`<PASTE_YOUTUBE_LINK_HERE>` (≤ 7 minutes: mobile app prediction + Swagger UI tests + model
performance discussion)

## Repository Structure
```
linear_regression_model/
├── summative/
│   ├── linear_regression/
│   │   ├── multivariate.ipynb        # EDA, feature engineering, 4-model comparison, best model
│   │   ├── data/
│   │   │   ├── build_dataset.py      # fetches & merges the World Bank data
│   │   │   └── africa_out_of_school.csv
│   │   └── models/                   # saved best model, scaler, feature order (joblib)
│   ├── API/
│   │   ├── prediction.py             # FastAPI app: /predict, /retrain, CORS, Pydantic schema
│   │   └── requirements.txt
│   └── FlutterApp/                   # single-page Flutter prediction UI
├── pyproject.toml                    # uv-managed Python deps (notebook + API)
├── render.yaml                       # Render deployment blueprint for the API
└── README.md
```

## Running the Notebook
```bash
cd linear_regression_model
uv sync
uv run jupyter notebook summative/linear_regression/multivariate.ipynb
```

## Running the API Locally
```bash
cd linear_regression_model
uv sync
uv run uvicorn prediction:app --reload --app-dir summative/API --port 8000
# Swagger UI: http://127.0.0.1:8000/docs
```

### CORS configuration
`prediction.py` restricts `allow_origins` to an explicit list (localhost dev ports + the
deployed Flutter web origin) rather than `"*"`, restricts `allow_methods` to `GET`/`POST` only
(no `PUT`/`DELETE`), restricts `allow_headers` to `Content-Type`, and sets
`allow_credentials=False` since the API uses no cookies/session auth. This follows the
principle of least privilege: only what the Flutter client actually needs is allowed.

### Deploying the API to Render
1. Push this repository to GitHub.
2. On [render.com](https://render.com) → **New +** → **Blueprint**, connect the repo (it will
   read `render.yaml`), or manually create a **Web Service** with:
   - Root directory: `summative/API`
   - Build command: `pip install -r requirements.txt`
   - Start command: `uvicorn prediction:app --host 0.0.0.0 --port $PORT`
3. Once deployed, visit `https://<your-service>.onrender.com/docs` to confirm Swagger UI loads,
   and paste that URL into the README and Flutter app as described above.

### Triggering a retrain
```bash
curl -X POST https://<your-service>.onrender.com/retrain \
  -F "file=@new_data.csv"
```
`new_data.csv` must contain the same columns as `africa_out_of_school.csv`. The endpoint
appends the new rows to the dataset, re-fits the scaler and a fresh `RandomForestRegressor`,
and hot-swaps the in-memory model so `/predict` immediately reflects the update.

## Running the Mobile App
```bash
cd linear_regression_model/summative/FlutterApp
flutter pub get
# 1. Update kApiBaseUrl in lib/main.dart with your deployed Render URL
# 2. Run on a connected device/emulator, or in Chrome:
flutter run                # pick a device
flutter run -d chrome      # or run as a web app
```
The app is a single page: numeric fields for every model input (year, GDP per capita, education
spend, under-5 mortality, rurality, health spend, internet access, unemployment, life
expectancy, population), a region dropdown, a **Predict** button, and a result/error display
area that shows either the predicted out-of-school rate or a validation/network error message.
