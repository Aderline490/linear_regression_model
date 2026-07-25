"""
Builds the dataset for the mission: predicting the rate of primary-school-age
children who are OUT OF SCHOOL across African countries, from socioeconomic,
health and demographic drivers.

Source: World Bank Open Data API (https://data.worldbank.org), a public,
authentication-free API — no Kaggle credentials required. Pulls real,
country-year level indicators for all 54 African countries, 2000-2022.

Run:
    python3 build_dataset.py
Produces:
    africa_out_of_school.csv
"""

import json
import time
import urllib.request

import pandas as pd

COUNTRIES = (
    "AGO;BDI;BEN;BFA;BWA;CAF;CIV;CMR;COD;COG;COM;CPV;DJI;DZA;EGY;ERI;ETH;GAB;"
    "GHA;GIN;GMB;GNB;GNQ;KEN;LBR;LBY;LSO;MAR;MDG;MLI;MOZ;MRT;MUS;MWI;NAM;NER;"
    "NGA;RWA;SDN;SEN;SLE;SOM;SSD;STP;SWZ;SYC;TCD;TGO;TUN;TZA;UGA;ZAF;ZMB;ZWE"
)

INDICATORS = {
    "SE.PRM.UNER.ZS": "out_of_school_pct",       # TARGET
    "NY.GDP.PCAP.CD": "gdp_per_capita_usd",
    "SE.XPD.TOTL.GD.ZS": "gov_edu_exp_pct_gdp",
    "SH.DYN.MORT": "under5_mortality_per1000",
    "SP.RUR.TOTL.ZS": "rural_pop_pct",
    "SH.XPD.CHEX.PC.CD": "health_exp_per_capita_usd",
    "IT.NET.USER.ZS": "internet_users_pct",
    "SL.UEM.TOTL.ZS": "unemployment_pct",
    "SP.DYN.LE00.IN": "life_expectancy_years",
    "SP.POP.TOTL": "population_total",
}

BASE_URL = "https://api.worldbank.org/v2/country/{countries}/indicator/{code}"


def fetch_indicator(code: str) -> pd.DataFrame:
    url = BASE_URL.format(countries=COUNTRIES, code=code) + "?format=json&date=2000:2022&per_page=2000"
    with urllib.request.urlopen(url) as resp:
        payload = json.load(resp)
    rows = payload[1] if len(payload) > 1 and payload[1] else []
    records = [
        {
            "country": r["country"]["value"],
            "iso3": r["countryiso3code"],
            "region": r["country"]["value"],  # placeholder, replaced below
            "year": int(r["date"]),
            INDICATORS[code]: r["value"],
        }
        for r in rows
    ]
    return pd.DataFrame(records)


def fetch_region_map() -> dict:
    url = f"https://api.worldbank.org/v2/country/{COUNTRIES}?format=json&per_page=100"
    with urllib.request.urlopen(url) as resp:
        payload = json.load(resp)
    return {c["id"]: c["region"]["value"].strip() for c in payload[1]}


def main():
    region_map = fetch_region_map()

    merged = None
    for code in INDICATORS:
        print(f"Fetching {code} ({INDICATORS[code]})...")
        df = fetch_indicator(code)
        df = df.drop(columns=["region"])
        if merged is None:
            merged = df
        else:
            merged = merged.merge(df, on=["country", "iso3", "year"], how="outer")
        time.sleep(0.2)

    merged["region"] = merged["iso3"].map(region_map)
    merged = merged.dropna(subset=["out_of_school_pct"]).reset_index(drop=True)

    out_path = "africa_out_of_school.csv"
    merged.to_csv(out_path, index=False)
    print(f"Saved {len(merged)} rows x {merged.shape[1]} columns -> {out_path}")


if __name__ == "__main__":
    main()
