"""
FastAPI service exposing the best-performing regression model trained in
summative/linear_regression/multivariate.ipynb, which predicts the percentage
of primary-school-age children who are OUT OF SCHOOL in a given African
country-year, from socioeconomic, health and demographic indicators.

Run locally:
    uv run uvicorn prediction:app --reload --port 8000
Then open http://127.0.0.1:8000/docs for the Swagger UI.
"""

import os
from typing import Literal

import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

MODELS_DIR = os.path.join(
    os.path.dirname(__file__), "..", "linear_regression", "models"
)
DATA_PATH = os.path.join(
    os.path.dirname(__file__), "..", "linear_regression", "data", "africa_out_of_school.csv"
)
FEATURE_ORDER = joblib.load(os.path.join(MODELS_DIR, "feature_order.joblib"))

_state = {
    "model": joblib.load(os.path.join(MODELS_DIR, "best_model.joblib")),
    "scaler": joblib.load(os.path.join(MODELS_DIR, "scaler.joblib")),
}

app = FastAPI(
    title="Africa Out-of-School Children Rate Predictor",
    description=(
        "Predicts the percentage of primary-school-age children who are out of "
        "school in an African country-year, to help target education, health and "
        "family-placement programs for vulnerable children."
    ),
    version="1.0.0",
)

# --- CORS -------------------------------------------------------------------
# Reasoning:
#   * allow_origins is an explicit allow-list, never "*" — only the Flutter app's
#     known runtime origins (local dev server + the deployed web/mobile client
#     origin placeholder below) may call this API from a browser context.
#   * allow_methods is restricted to GET (docs/health) and POST (predict/retrain) —
#     this API never needs PUT/DELETE, so they stay blocked.
#   * allow_headers is restricted to what the client actually sends (JSON content
#     type); we do not allow arbitrary custom headers.
#   * allow_credentials is False because this API uses no cookies/session auth —
#     enabling it would only widen the attack surface for no functional benefit.
ALLOWED_ORIGINS = [
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:8080",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8080",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)


class PredictionInput(BaseModel):
    year: int = Field(..., ge=2000, le=2035, description="Calendar year")
    gdp_per_capita_usd: float = Field(..., ge=100, le=20000, description="GDP per capita, current US$")
    gov_edu_exp_pct_gdp: float = Field(..., ge=0, le=15, description="Government education expenditure, % of GDP")
    under5_mortality_per1000: float = Field(..., ge=0, le=500, description="Under-5 mortality rate, per 1,000 live births")
    rural_pop_pct: float = Field(..., ge=0, le=100, description="Rural population, % of total")
    health_exp_per_capita_usd: float = Field(..., ge=0, le=800, description="Health expenditure per capita, current US$")
    internet_users_pct: float = Field(..., ge=0, le=100, description="Individuals using the internet, % of population")
    unemployment_pct: float = Field(..., ge=0, le=40, description="Unemployment, % of total labor force")
    life_expectancy_years: float = Field(..., ge=10, le=85, description="Life expectancy at birth, years")
    population_total: float = Field(..., ge=50_000, le=200_000_000, description="Total population")
    region: Literal["Sub-Saharan Africa", "MENA"] = Field(..., description="World Bank region grouping")


class PredictionOutput(BaseModel):
    predicted_out_of_school_pct: float
    model_used: str


class RetrainResponse(BaseModel):
    message: str
    rows_used: int
    test_mse: float
    test_r2: float


def _build_feature_row(payload: PredictionInput) -> pd.DataFrame:
    row = {
        "year": payload.year,
        "gdp_per_capita_usd": np.log1p(payload.gdp_per_capita_usd),
        "gov_edu_exp_pct_gdp": payload.gov_edu_exp_pct_gdp,
        "under5_mortality_per1000": payload.under5_mortality_per1000,
        "rural_pop_pct": payload.rural_pop_pct,
        "health_exp_per_capita_usd": payload.health_exp_per_capita_usd,
        "internet_users_pct": payload.internet_users_pct,
        "unemployment_pct": payload.unemployment_pct,
        "life_expectancy_years": payload.life_expectancy_years,
        "population_total": np.log1p(payload.population_total),
        "is_mena": 1 if payload.region == "MENA" else 0,
    }
    return pd.DataFrame([row])[FEATURE_ORDER]


@app.get("/")
def root():
    return {"message": "See /docs for the Swagger UI and available endpoints."}


@app.post("/predict", response_model=PredictionOutput)
def predict(payload: PredictionInput):
    features = _build_feature_row(payload)
    features_scaled = _state["scaler"].transform(features)
    prediction = float(_state["model"].predict(features_scaled)[0])
    prediction = max(0.0, min(100.0, prediction))
    return PredictionOutput(
        predicted_out_of_school_pct=round(prediction, 2),
        model_used=type(_state["model"]).__name__,
    )


@app.post("/retrain", response_model=RetrainResponse)
def retrain(file: UploadFile = File(...)):
    """
    Retrains the model from scratch on the original dataset PLUS newly uploaded
    rows (a CSV with the same columns as africa_out_of_school.csv), then hot-swaps
    the in-memory model/scaler so /predict immediately uses the updated model.
    """
    if not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="Please upload a .csv file.")

    try:
        new_data = pd.read_csv(file.file)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Could not parse CSV: {exc}")

    base = pd.read_csv(DATA_PATH)
    required_cols = set(base.columns)
    if not required_cols.issubset(set(new_data.columns)):
        missing = required_cols - set(new_data.columns)
        raise HTTPException(status_code=400, detail=f"Uploaded CSV is missing columns: {sorted(missing)}")

    combined = pd.concat([base, new_data[base.columns]], ignore_index=True).drop_duplicates()
    combined.to_csv(DATA_PATH, index=False)

    combined = combined.dropna(subset=["out_of_school_pct"])
    combined["is_mena"] = (combined["region"] == "Middle East, North Africa, Afghanistan & Pakistan").astype(int)

    impute_cols = ["gdp_per_capita_usd", "gov_edu_exp_pct_gdp", "health_exp_per_capita_usd",
                   "internet_users_pct", "unemployment_pct"]
    region_medians = combined.groupby("region")[impute_cols].median()
    for col in impute_cols:
        combined[col] = combined[col].fillna(combined["region"].map(region_medians[col]))

    combined["gdp_per_capita_usd"] = np.log1p(combined["gdp_per_capita_usd"])
    combined["population_total"] = np.log1p(combined["population_total"])

    X = combined[FEATURE_ORDER]
    y = combined["out_of_school_pct"]
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    model = RandomForestRegressor(n_estimators=300, max_depth=10, min_samples_leaf=2, random_state=42, n_jobs=-1)
    model.fit(X_train_scaled, y_train)

    test_pred = model.predict(X_test_scaled)
    test_mse = float(mean_squared_error(y_test, test_pred))
    test_r2 = float(r2_score(y_test, test_pred))

    joblib.dump(model, os.path.join(MODELS_DIR, "best_model.joblib"))
    joblib.dump(scaler, os.path.join(MODELS_DIR, "scaler.joblib"))
    joblib.dump(region_medians, os.path.join(MODELS_DIR, "region_medians.joblib"))

    _state["model"] = model
    _state["scaler"] = scaler

    return RetrainResponse(
        message="Model retrained and hot-swapped successfully.",
        rows_used=len(combined),
        test_mse=round(test_mse, 3),
        test_r2=round(test_r2, 3),
    )
