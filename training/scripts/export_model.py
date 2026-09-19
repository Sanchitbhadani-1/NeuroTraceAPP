import sys
sys.path.insert(0, "scripts")

from evaluate import cv_scores, models
from neurotrace.synth import create_spiral_synth
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features

import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression

import json


csv_path = sys.argv[1]
df = pd.read_csv(csv_path)

df = df[df["release"] == "hw_dataset"].reset_index(drop=True)
# filter out only the rows of patients from hw_dataset (the dataset
# with BOTH a control and a experimental)

feature_cols = []
for c in df.columns:
    if c.startswith("spiral_"):
        feature_cols.append(c)

X = df[feature_cols].values
# Removes the pandas extras and converts it into a np array

y = df["label"].values
# Removes the pandas extras and converts it into a np array

scaler = StandardScaler().fit(X)
X_std = scaler.transform(X)

model = LogisticRegression(C=0.5, class_weight="balanced", max_iter=2000).fit(X_std, y)
# Build the model with balanced weight to the classes

aucs, baccs = cv_scores(X, y, df["subject_id"].values, models()["logreg"], 5, 30)
# Calculate the AUC and balanced AUC for each trial

# Print the 5th, 50th, and 95th pecentile of the AUC and balanced AUC for the 30 trials
cv_auc = np.percentile(aucs, [5, 50, 95]).tolist()
cv_bacc = np.percentile(baccs, [5, 50, 95]).tolist()
print("AUC  5/50/95:", cv_auc)
print("bacc 5/50/95:", cv_bacc)

model_out = {
    "version": 1,
    "task": "spiral",
    "featureOrder": feature_cols,
    "mean": scaler.mean_.tolist(),
    "scale": scaler.scale_.tolist(),
    "weights": model.coef_[0].tolist(),
    "bias": float(model.intercept_[0]),
    "trainedOn": {
        "date": "2026-09-19",
        "sources": ["uci395:hw_dataset"],
        "nHealthy": int((y == 0).sum()),
        "nPatients": int((y == 1).sum()),
        "cvAuc": cv_auc,
        "cvBalancedAccuracy": cv_bacc,
    },
}

with open("../app/model.json", "w") as f:
    json.dump(model_out, f, indent=2)


healthy = df[df["label"] == 0]
healthy_scores = model.predict_proba(scaler.transform(healthy[feature_cols].values))[:, 1]

percentiles_out = {
    "version": 1,
    "reference": {
        "description": "healthy adults",
        "n": int(len(healthy)),
        "sources": ["uci395:hw_dataset"],
    },
    "features": {c: sorted(healthy[c].tolist()) for c in feature_cols},
    "score": sorted(healthy_scores.tolist()),
}

with open("../app/percentiles.json", "w") as f:
    json.dump(percentiles_out, f, indent=2)

print("wrote ../app/model.json and ../app/percentiles.json")