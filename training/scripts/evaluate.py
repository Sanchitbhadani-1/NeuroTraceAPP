# EVAULUATE.PY IS TO TEST DIFFERENT MODELS WITH DIFFERENT FEATURE SETS, AND SEE WHICH COMBINATION WORKS BEST
# EACH MODEL IS TESTED WITH REPEATED CROSS VALIDATION, SO EVERY PERSON IS SCORED BY A MODEL THAT NEVER SAW THEM

import argparse
import warnings

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

BROKEN = {"spiral_tremor_6_12"}
# After testing, this feature is broken and should not be used.

# Figure out which features are best for the model
def feature_sets(df):

    # Create an empty list to hold the names of usable features and iterate through the columns of the DataFrame
    usable = []
    for column in df.columns:

        # If the column is not META, include it
        if column not in META:
            filled = df[column].notna().mean()

            # Keep measurement columns that are filled in for more than half the people
            if filled > 0.5:
                usable.append(column)

    # Create empty lists for the three kinds of measurements
    base = []
    pressure = []
    inair = []

    # Group each usable column by the first word of its name
    for column in usable:

        # Spiral and writing measurements are the main set
        if column.startswith("spiral_") or column.startswith("writing_"):
            base.append(column)

        # Measurements of pressure is in a seperate set
        elif column.startswith("pressure_"):
            pressure.append(column)

        # Measurements of in-air time of the pen is in a sseperate set
        elif column.startswith("inair_"):
            inair.append(column)

    # Start the dictionary of sets with the main measurements
    sets = {"base": base}

    # Make a new list of the main measurements, leaving out features that don't work
    trusted = []
    for column in base:
        if column not in BROKEN:
            trusted.append(column)

    # Only add the trusted set if it leaves out at least one feature
    if len(trusted) < len(base):
        sets["base_trusted"] = trusted

    # If there are pressure measurements, test how they do alone and how they do with the base set
    if len(pressure) > 0:
        sets["pressure_only"] = pressure
        sets["base+pressure"] = base + pressure

    # If there are in-air time measurements, test how they do alone and how they do with the base set
    if len(inair) > 0:
        sets["inair_only"] = inair
        sets["base+inair"] = base + inair

    # If there are in-air time and pressure measurements, test how they do together with the base set
    if len(pressure) > 0 and len(inair) > 0:
        sets["base+pressure+inair"] = base + pressure + inair

    # Create empty lists for the three kinds of main measurements
    geom = []
    motion = []
    tremor = []

    # Sort the main measurements by what they measure
    for column in base:

        # If measurements are for geometry, add them to the geometry list
        if "deviation" in column or "reversals" in column:
            geom.append(column)

        # If measurements are for motion, add them to the motion list
        if "speed" in column or "ldlj" in column or "sparc" in column or "duration" in column:
            motion.append(column)

        # If measurements are for tremor, add them to the tremor list
        if "tremor" in column:
            tremor.append(column)

    # Add each kind as its own set
    if len(geom) > 0:
        sets["geometry_only"] = geom
    if len(motion) > 0:
        sets["motion_only"] = motion
    if len(tremor) > 0:
        sets["tremor_only"] = tremor

    # Give back each set, so that the model can be tested on each one
    return sets


# Make a new logistic regression model
def make_logreg():

    # Fill in a missing value with the middle value of that column
    fill_missing = SimpleImputer(strategy="median")

    # Put every measurement on the same scale
    same_scale = StandardScaler()

    # Build the logistic regression model, use balanced because the dataset is unbalanced
    model = LogisticRegression(C=0.5, class_weight="balanced", max_iter=2000)

    # Join the three steps into one pipeline and return
    return make_pipeline(fill_missing, same_scale, model)


# Make a new gradient boosting model to compare against the logistic regression model
def make_gboost():
    return HistGradientBoostingClassifier(
        max_depth=2,
        max_iter=60,
        learning_rate=0.1,
        min_samples_leaf=4,
        class_weight="balanced",
    )


# Returns a dictonary of the model objects we want to test
def models():

    return {"logreg": make_logreg, "gboost": make_gboost}


# Repeated cross validation, used to create our AUC and balanced accuracy scores for each model and feature set
def cv_scores(X, y, groups, make_model, n_splits, repeats):

    # Create empty lists for the AUC and balanced accuracy from each repeat
    aucs = []
    baccs = []

    # Run the whole test again for each repeat, with a different random split each time
    for seed in range(repeats):

        # Split people into groups
        # Used for the cross validation, and leave each group out one at a time while training on the others
        cv = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)

        # One empty score per person, filled in as each group gets tested
        prob = np.full(len(y), np.nan)

        # Take turns leaving out one group
        for train_rows, test_rows in cv.split(X, y, groups):

            # Train a new model on the other groups
            model = make_model()
            model.fit(X[train_rows], y[train_rows])

            # Score by testing on the group left out
            chances = model.predict_proba(X[test_rows])
            prob[test_rows] = chances[:, 1]

        # How well the scores rank patients above healthy people
        auc = roc_auc_score(y, prob)
        aucs.append(auc)

        # Set the logistic threshold at 0.5, check see how many patients are correctly classified
        guesses = prob >= 0.5
        bacc = balanced_accuracy_score(y, guesses)
        baccs.append(bacc)

    # Return one score of each per repeat, so the average can be taken and the range can be calculated
    return np.array(aucs), np.array(baccs)


# Turn the repeat scores into text, the middle score and the range 90% of them fall in
def fmt(a):
    return f"{np.median(a):.3f}  [{np.percentile(a, 5):.3f}-{np.percentile(a, 95):.3f}]"
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--release", default=None)
    ap.add_argument("--repeats", type=int, default=30)
    ap.add_argument("--splits", type=int, default=5)
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    if args.release:
        df = df[df["release"] == args.release].reset_index(drop=True)

    y = df["label"].values
    groups = df["subject_id"].values

    n0, n1 = (y == 0).sum(), (y == 1).sum()
    print(f"n = {len(df)}  ({n0} HC, {n1} PD)   majority-class accuracy = {max(n0, n1) / len(df):.3f}")
    print(f"{args.splits}-fold, {args.repeats} repeats, patient-level splits. median [5th-95th pct]\n")

    if df["fs_raw"].nunique() > 1:
        a, _ = cv_scores(df[["fs_raw"]].values, y, groups, models()["logreg"], args.splits, args.repeats)
        print(f"CONFOUND  fs_raw alone predicts the label at AUC {fmt(a)}")
        print("          NOT a leakage test - fs_raw tracks the dataset and so does the")
        print("          label, so any feature that works must correlate with it. The real")
        print("          test holds the person fixed and changes only the rate.\n")

    warnings.filterwarnings("ignore")
    for fname, cols in feature_sets(df).items():
        X = df[cols].values.astype(float)
        print(f"[{fname}]  {len(cols)} features")
        for mname, make in models().items():
            a, b = cv_scores(X, y, groups, make, args.splits, args.repeats)
            print(f"   {mname:7s}  AUC {fmt(a)}   bal.acc {fmt(b)}")
        print()


if __name__ == "__main__":
    main()
