# NeuroTrace

**NeuroTrace turns an ordinary iPad into a motor-function measurement tool powered by machine learning.**

You draw three spirals with an Apple Pencil or your finger. NeuroTrace measures 12 things about how you drew them (speed, smoothness, tremor and how far the line wanders), combines them with a machine learning model trained on spiral drawings from 112 people with and without Parkinson's, and shows where you sit compared with a group of healthy adults. Over time it tracks how those numbers change, and it gives people living with Parkinson's at-home exercises, a medication diary and a summary to bring to their doctor.

Built by **Sanchit Bhadani**, **Aryan Modi** and **Mihir Malladi** for the **2026 Congressional App Challenge**.

> **NeuroTrace is a measurement, not a diagnosis.** It cannot tell anyone whether they have Parkinson's or any other condition. It is a school project, not a medical device, and it has not been reviewed by the FDA.

---

## Contents

1. [Why we built it](#why-we-built-it)
2. [Who it's for](#who-its-for)
3. [What the app does](#what-the-app-does)
4. [How the spiral check-in works](#how-the-spiral-check-in-works)
5. [The 12 measurements](#the-12-measurements)
6. [The model and how well it works](#the-model-and-how-well-it-works)
7. [The training data](#the-training-data)
8. [What we found along the way](#what-we-found-along-the-way)
9. [Tech stack](#tech-stack)
10. [Repository layout](#repository-layout)
11. [Running it yourself](#running-it-yourself)
12. [Testing](#testing)
13. [Privacy](#privacy)
14. [Limitations](#limitations)
15. [Team](#team)
16. [Use of AI](#use-of-ai)
17. [References](#references)

---

## Why we built it

Parkinson's disease is one of the fastest growing neurological disorders in the world, and nearly 90,000 people in the U.S. are diagnosed with it every year. There is no single test for it. Doctors diagnose it from symptoms and an exam.

The biggest delay often comes before anyone sees a doctor. In one study of newly diagnosed patients, people waited a **median of 11 months** between their first movement symptoms and their first visit to a doctor about them. Once they went, diagnosis took a median of about one month ([Breen et al., 2013](https://pubmed.ncbi.nlm.nih.gov/23572347/)).

Early changes are small and easy to blame on age, stress or being tired. A slightly smaller, slower or shakier spiral is hard to notice yourself, but it can be measured. NeuroTrace's job is not to diagnose. It gives people a clear, specific reason to make that appointment sooner, and a record to bring with them.

---

## Who it's for

**People noticing early signs.** People with possible early symptoms who aren't sure whether it's Parkinson's. NeuroTrace measures their movement from three spirals, flags movement patterns linked to Parkinson's with a machine learning model, and gives them a clear reason to see a doctor sooner.

**People living with Parkinson's.** Diagnosed patients who want to improve their fine motor control. NeuroTrace gives them at-home exercises based on real rehab techniques, tracks their progress and medication timing, and makes a summary to bring to their doctor.

---

## What the app does

### Testing

- **Spiral check-in.** Trace three spirals from the center out. NeuroTrace checks each one is a real attempt at the spiral, measures it, and scores the three together.
- **Finger tapping.** Tap your thumb and index finger together in front of the iPad's camera. Apple's Vision framework tracks your hand, and NeuroTrace measures tapping speed, rhythm and whether you slow down over the test. The camera picture never leaves the iPad and is never saved, only the numbers are kept.

### Results

- A result level out of three: **Typical**, **Above** or **Well above** the typical range of the healthy reference group.
- Every measurement placed among the reference group, in plain words, for example "higher than 82% of the reference group."
- The measurements that stood out the most.
- Your drawing shown over the smoothed version the measurements are taken from, a replay of it at the speed you drew it, and a chart of your speed along the line.
- What the result means and what you can do next.

NeuroTrace never shows a probability or a "chance you have Parkinson's." The model's score is only used to find where you sit among healthy people.

### Progress

Your first and latest check-in side by side, with both drawings replaying together and every measurement compared. It only compares check-ins done with the same hand and the same input (Pencil or finger), so the comparison is fair.

### Training

Four exercises, each with 10 levels that go up after enough good tries and down after too many misses in a row:

| Exercise | What you do | What it practices |
|---|---|---|
| **Big writing** | Write a row of tall loops that touch a dashed line | Handwriting size, which often shrinks with Parkinson's |
| **Steady tracing** | Watch a dot trace a spiral, picture it, then trace it yourself as the guide fades at higher levels | Accuracy and control, using watching and picturing the movement first |
| **Rhythm** | Follow a dot along a wave in time with metronome clicks | Keeping a steady rhythm with an outside beat |
| **Hand skills** | Tap shrinking circles before they disappear | Reaction time and precision |

The Training tab suggests a focus for the day and shows what you did this week.

### Care

- **Medication diary.** Log a dose with one tap. NeuroTrace saves how long it has been since your last dose with every check-in, and shows how your results line up with your dose times. It never gives advice about doses.
- **Doctor summary.** Makes a PDF with your check-ins, finger tapping, practice and medication timing, ready to print or share with your doctor.
- **Home safety scan.** Take a photo of a room and get a short list of ideas to make it safer, like clearing a walkway or adding a night light. The photo is sent to Google's Gemini model through Firebase, and NeuroTrace's own rules check the ideas before showing them. This is the only feature that sends anything off the iPad, and it asks first.

### Settings and accessibility

Light and dark mode, seven accent colors, a Reduced Motion setting, large readable fonts (Atkinson Hyperlegible Next and Newsreader), VoiceOver labels on charts and drawings, and a way to delete every check-in. Optional email accounts use Firebase Authentication. An account only signs you in, and your data stays on the iPad.

### Data collection mode

A separate mode for collecting spirals from volunteers, with a consent step, participant ids that don't include names, and an export to a JSON file. We built it to collect spirals on the iPad itself, so future versions of the model can be trained on the same device people use.

---

## How the spiral check-in works

```
 Your 3 spirals
      │
      ▼
 1. Clean up        remove bad points, cut off the still parts at the start and end,
                    put every drawing on an even 100 points per second, center and scale it,
                    and smooth out anything faster than 15 times per second
      │
      ▼
 2. Measure         12 numbers per spiral (below), averaged over the 3 spirals
      │
      ▼
 3. Standardize     each number compared with the healthy reference group,
                    in steps of the healthy group's spread
      │
      ▼
 4. Combine         a logistic regression model turns the 12 numbers into one score
      │
      ▼
 5. Place           the score and every measurement placed among the healthy reference group
      │
      ▼
 6. Result level    below the 75th percentile is Typical, 75th to 95th is Above,
                    above the 95th is Well above
```

All of this runs **on the iPad**, with no server. The cleanup and the measurements were first written in Python for training, then written again in JavaScript for the app. A parity test checks that both give the same 12 numbers on the same drawings, matching to about 13 decimal places. The iPad app runs that same JavaScript inside Swift with Apple's JavaScriptCore, so the website and the iPad app score drawings exactly the same way.

---

## The 12 measurements

Every measurement is taken from the cleaned up drawing.

| Measurement | What it measures |
|---|---|
| `spiral_duration` | How long the spiral took, in seconds |
| `spiral_max_deviation` | The farthest the line strays from a smooth spiral fitted to your own drawing |
| `spiral_mean_deviation` | How far the line strays on average |
| `spiral_std_deviation` | How much that straying changes along the line |
| `spiral_major_reversals` | How many times the pen pulls back toward the center by more than 10% of its distance |
| `spiral_mean_speed` | Average pen speed |
| `spiral_std_speed` | How much the pen speed changes |
| `spiral_ldlj` | Log dimensionless jerk, a measure of smoothness based on how suddenly the speed changes |
| `spiral_sparc` | Spectral arc length, a measure of smoothness based on the speed's frequencies ([Balasubramanian et al., 2015](https://doi.org/10.1186/s12984-015-0090-9)) |
| `spiral_tremor_4_6` | Shaking at 4 to 6 times per second, the usual range of Parkinson's tremor |
| `spiral_tremor_6_12` | Shaking at 6 to 12 times per second |
| `spiral_tremor_dominant_hz` | The strongest shaking speed between 3 and 12 times per second |

The deviation measurements compare your line with a spiral fitted to **your own drawing**, not a fixed template, so a spiral that is bigger, smaller or drawn the other way isn't counted as wrong.

---

## The model and how well it works

- **Model.** Logistic regression (scikit-learn) with balanced class weights and strong regularization (`C = 0.05`), since there are only 112 people and 12 measurements.
- **Standardization.** Each dataset is compared with **its own healthy people** before the two are combined, so "+2" means "two steps of healthy spread above normal" on either tablet.
- **Testing.** 5-fold cross-validation that keeps each person in one fold only, stratified by diagnosis and repeated 30 times with different random splits. Every person is scored by a model that never saw them during training.

| | Result (median, with the range 90% of the 30 repeats fall in) |
|---|---|
| **Cross-validated AUC, both datasets** | **0.72** (0.71 to 0.74) |
| Balanced accuracy | 0.64 (0.61 to 0.67) |
| AUC within UCI | 0.87 (0.84 to 0.89) |
| AUC within PaHaW | 0.62 (0.60 to 0.64) |

AUC measures how well the model separates two groups, where 1.0 is perfect and 0.5 is a coin flip. We report the honest combined number. It is lower than the number on UCI alone, and we explain why below.

The measurements the model leans on most are smoothness (`spiral_sparc`, `spiral_ldlj`), how much the line strays (`spiral_std_deviation`, `spiral_mean_deviation`) and pull-backs toward the center (`spiral_major_reversals`).

The trained model is saved as `model.json`, and the healthy reference group as `reference.json`. Both ship with the app.

---

## The training data

| Dataset | People we used | Where it's from | Access |
|---|---|---|---|
| **UCI** *Parkinson Disease Spiral Drawings Using Digitized Graphics Tablet* | 40 (15 healthy, 25 with Parkinson's) | Istanbul University, Turkey | Free public download |
| **PaHaW** *Parkinson's Disease Handwriting Database* | 72 (36 healthy, 36 with Parkinson's) | Brno, Czech Republic | Research license, signed by our school |
| **Total** | **112 (51 healthy, 61 with Parkinson's)** | | |

Both were recorded on Wacom drawing tablets.

**PaHaW is license-restricted, and none of its recordings are in this repository.** Its raw files stay on one team member's computer, and only summary numbers (measurement tables and model scores) are used anywhere else. No individual PaHaW drawing is shown, plotted or shared. The `data/` folder and every `.svc` file are listed in `.gitignore`.

The healthy reference group currently comes from the 36 healthy PaHaW participants, as a stand-in until we have enough spirals recorded on iPads. The app says so on the results screen.

More detail on every dataset we looked at is in [`docs/DATASETS.md`](docs/DATASETS.md).

---

## What we found along the way

- **A result that looked too good was wrong.** In the UCI data, almost every healthy person was recorded at 143 samples per second and every patient at 111. The sample rate alone predicted Parkinson's with an AUC of about 0.98. Putting every drawing on the same 100 points per second fixed it, and testing only on people the model never saw keeps us honest.
- **One dataset was a copy of another.** A second UCI dataset was a re-release of the same 40 people, with identical files. Using both would have counted the same patients twice.
- **File names can lie.** Some UCI patient files start with `H_`, which looks like "healthy." Labels come from the folder a file is in, never its name.
- **Some measurements measured the tablet, not the person.** A feature that counted every tiny back-and-forth of the radius was really counting the tablet's pixel grid, and it pointed the wrong way. We replaced it with one that only counts real pull-backs.
- **The drawing has to be compared with itself.** UCI participants drew about 2.75 turns clockwise, and our guide spiral had almost 4 turns counterclockwise. Measuring distance from a fixed template measured that mismatch, so we fit a spiral to each drawing instead.
- **Medication changes the picture.** The model separates PaHaW's two groups less well than UCI's. We think the main reason is that PaHaW's patients were being treated with medication, which can reduce tremor and make their drawings look closer to healthy ones.
- **Some datasets can't be used at all.** NewHandPD had no pen positions or timestamps, only pen sensor voltages.

---

## Tech stack

| | |
|---|---|
| **Languages** | Swift, JavaScript, Python |
| **iPad app** | SwiftUI, UIKit, Vision (hand tracking), JavaScriptCore, Swift Charts |
| **Machine learning** | scikit-learn, NumPy, SciPy, pandas, Matplotlib |
| **Cloud and AI** | Firebase (Authentication, App Check, AI Logic), Google Gemini for the home safety scan |
| **Tools** | Xcode, Node.js and esbuild, pytest, GitHub |
| **Data** | PaHaW and UCI Parkinson's handwriting datasets |

The website version in `app/` is plain HTML, CSS and JavaScript modules with no framework and no build step.

---

## Repository layout

```
NeuroTrace-App/
├── ios/                          The iPad app
│   ├── NeuroTrace/
│   │   ├── App/                  App model, theme, shared components, text, drawing pad, camera, PDF, Firebase
│   │   ├── Core/                 Scoring, storage, check-in records, and the Swift side of every JavaScript module
│   │   ├── Screens/              One file per screen
│   │   └── Resources/            model.json, reference.json, fonts, and nt-core.js (the bundled JavaScript)
│   ├── NeuroTraceTests/          Swift tests, including the Swift and JavaScript parity test
│   ├── js/                       core.js (what gets bundled) and build.sh (bundles it with esbuild)
│   └── NeuroTrace.xcodeproj
│
├── app/                          The website version, and the JavaScript the iPad app also runs
│   ├── nt-signal.js              Math helpers (interpolation, gradients, least squares, FFT)
│   ├── nt-filters.js             Butterworth filter, forward and backward filtering, Welch's method
│   ├── nt-features.js            Cleanup and the 12 spiral measurements
│   ├── score.js                  Standardizing, the model, percentiles and the result level
│   ├── train.js                  Exercise levels and scoring
│   ├── tapping.js                Finger tapping measurements
│   ├── meds.js                   Medication timing
│   ├── hands.js                  Which hand the camera sees
│   ├── homescan.js               Rules that check the home scan ideas
│   ├── app.js, index.html, ...   The website's screens
│   └── tools/                    Node test scripts, including parity.mjs
│
├── training/                     The machine learning pipeline
│   ├── neurotrace/               preprocess.py, features.py, datasets.py, pahaw.py, synth.py, ...
│   ├── scripts/                  build_features.py, evaluate.py, export_model.py, plot_cv_scores.py, ...
│   ├── parity/                   make_reference.py, builds the Python and JavaScript parity test
│   ├── results/                  Measurement tables (summary numbers only)
│   └── tests/                    pytest tests
│
├── schema/trace.schema.json      The shape of a recorded drawing
├── docs/                         Datasets, the drawing format and the collected data format
└── requirements.txt              Python packages
```

---

## Running it yourself

### The iPad app

You need a Mac with a recent version of **Xcode** and an iPad on **iPadOS 17 or newer**. The iPad Simulator works too, but finger tapping needs a real camera.

1. Clone the repo and open `ios/NeuroTrace.xcodeproj` in Xcode.
2. Pick your iPad or a simulator and press **Run** (⌘R).

Everything except accounts and the home safety scan works with no setup. To turn those two on:

1. Make a Firebase project and add an iOS app with the bundle id from the Xcode project.
2. Turn on **Authentication** (email and password), **App Check**, and **AI Logic** with the Gemini Developer API.
3. Download `GoogleService-Info.plist` and drag it into `ios/NeuroTrace/` in Xcode. It's in `.gitignore`, so it never goes on GitHub.

**If you change any JavaScript** in `app/` that the iPad app uses (`nt-*.js`, `score.js`, `train.js`, `tapping.js`, `homescan.js`, `meds.js` or `hands.js`), bundle it again so the iPad app runs the new version. This needs Node.js.

```bash
ios/js/build.sh
```

### The website version

The website loads `model.json` and `reference.json`, so it has to be served, not opened as a file.

```bash
cd app
python3 -m http.server 8000
```

Then open <http://localhost:8000>.

### The machine learning pipeline

```bash
pip install -r requirements.txt
cd training
```

| Step | Command |
|---|---|
| Measure every UCI recording | `PYTHONPATH=. python scripts/build_features.py <uci_folder> results/features_uci395.csv` |
| Measure every PaHaW recording (needs the licensed data) | `PYTHONPATH=. python scripts/extract_pahaw.py <pahaw_folder> <pahaw_spreadsheet> results/features_pahaw.csv` |
| Compare models and measurement sets | `PYTHONPATH=. python scripts/evaluate.py results/features_combined.csv` |
| Train the final model and write `model.json` and `reference.json` | `PYTHONPATH=. python scripts/export_model.py results/features_uci395.csv results/features_pahaw.csv` |
| Draw the cross-validation chart | `PYTHONPATH=. python scripts/plot_cv_scores.py results/features_uci395.csv results/features_pahaw.csv` |

The datasets aren't in the repo. UCI can be downloaded from the [UCI Machine Learning Repository](https://archive.ics.uci.edu/). PaHaW needs a signed license agreement from its authors.

---

## Testing

| What | How |
|---|---|
| **Python** (cleanup, measurements, datasets, synthetic drawings) | `cd training && python -m pytest` |
| **Python and JavaScript give the same numbers** | `cd training && PYTHONPATH=. python parity/make_reference.py <uci_folder> parity/reference.json`, then `node app/tools/parity.mjs training/parity/reference.json` from the repo root |
| **JavaScript modules** (scoring, exercises, tapping, medication, hands, home scan, storage) | `node app/tools/<name>-check.mjs` |
| **Swift** (scoring, storage, exercises, tapping, medication, doctor summary, Swift and JavaScript parity) | Press ⌘U in Xcode |

The parity test runs real and synthetic drawings through both the Python and the JavaScript pipelines and requires all 12 measurements to match. It has caught bugs that looked fine by eye, like a filter seeded with the wrong sample.

---

## Privacy

- Your drawings, check-ins, finger tapping results, practice and medication diary are stored **only on your iPad**.
- Scoring happens on the iPad. No drawing is ever sent to a server.
- The finger tapping camera picture is processed live and never saved. Only the tap times are kept.
- An account only signs you in. Your data isn't uploaded to it.
- The home safety scan is the one feature that sends something off the iPad: the room photo goes to Google's Gemini model through Firebase. The app tells you before you take it, and it isn't required for anything else.
- You can delete every check-in from Settings.

---

## Limitations

We would rather say these openly than have someone find them.

- **It is not a diagnosis.** Many things change these measurements, like caffeine, being tired, sleep, anxiety, medication timing and cold hands.
- **It can't find Parkinson's before it starts.** By the time movement changes can be measured, the disease has usually been going for years.
- **The training data is small.** 112 people from two datasets, recorded on drawing tablets, not iPads.
- **The reference group is a stand-in.** It's the 36 healthy PaHaW participants, not people recorded on an iPad. We built the data collection mode to replace it.
- **The model works better on some data than others.** It separates UCI's groups well (AUC 0.87) and PaHaW's less well (AUC 0.62), which we think is mostly from medication.
- **It only tells Parkinson's apart from healthy.** It hasn't been trained to tell Parkinson's from essential tremor or other conditions.
- **It hasn't been tested in a clinical study.** That would need ethics approval, doctors' ratings to compare against, and the same people tested more than once.

---

## Team

| | |
|---|---|
| **Sanchit Bhadani** | Machine learning pipeline, the 12 measurements and their JavaScript version, the model, the iPad app and the video |
| **Aryan Modi** | Finger tapping test and home safety scan |
| **Mihir Malladi** | Rehab exercises and medication tracking |

Made for the 2026 Congressional App Challenge.

---

## Use of AI

AI was used to plan the app and for high level math sections in the ML pipeline. Additionally, it was used to check code and make it more readable.

The home safety scan feature uses Google's Gemini model inside the app, as described above.

---

## References

- Breen DP, Evans JR, Farrell K, Brayne C, Barker RA. *Determinants of delayed diagnosis in Parkinson's disease.* Journal of Neurology, 2013. <https://pubmed.ncbi.nlm.nih.gov/23572347/>
- Parkinson's Foundation. *Statistics: prevalence and incidence.* <https://www.parkinson.org/understanding-parkinsons/statistics>
- Isenkul ME, Sakar BE, Kursun O. *Improved spiral test using digitized graphics tablet for monitoring Parkinson's disease.* 2014. UCI Machine Learning Repository, *Parkinson Disease Spiral Drawings Using Digitized Graphics Tablet.*
- Drotár P, Mekyska J, Rektorová I, Masarová L, Smékal Z, Faundez-Zanuy M. *Evaluation of handwriting kinematics and pressure for differential diagnosis of Parkinson's disease.* Artificial Intelligence in Medicine, 2016. (PaHaW)
- Balasubramanian S, Melendez-Calderon A, Roby-Brami A, Burdet E. *On the analysis of movement smoothness.* Journal of NeuroEngineering and Rehabilitation, 2015. <https://doi.org/10.1186/s12984-015-0090-9>


