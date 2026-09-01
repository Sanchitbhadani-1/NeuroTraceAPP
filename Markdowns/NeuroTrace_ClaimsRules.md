# NeuroTrace — Claims and Wording Rules

Every claim in the app, the video, and the written submission has to pass through this. Run the final script and the submission text against it line by line before you send anything.

---

## THE MASTER RULE

Every claim you make must be about one of three things:

1. **What the software does** — "the app measures four dimensions and adjusts the next exercise"
2. **Where a technique came from** — "implements protocols shown in a randomized trial to improve X"
3. **What was measured** — "writing size increased 14% within the session"

Never about **what happens to the user's disease.** That is the line. Everything below is an application of it.

**The self-check:** *could someone disprove this with a study I haven't run?* If yes, reword it until the answer is no.

---

## RED FLAG WORDS

If any of these appear in your script or submission, stop and reread the sentence:

**ensures · guarantees · detects · diagnoses · screens · treats · cures · prevents · slows · improves · proves · accurate · effective**

None are banned outright. All of them are usually load-bearing in a sentence that overclaims.

---

## DIAGNOSIS AND SCREENING

| Don't say | Say |
|---|---|
| "Diagnoses Parkinson's" | "Measures motor features associated with Parkinson's" |
| "Detects Parkinson's" | "Measures motor features associated with Parkinson's" |
| "Screens the population for Parkinson's" | "A measurement for people who have already noticed a change" |
| "Model probability: 84%" | "6th percentile compared with our reference sample" |
| "Elevated risk" | "Outside the typical range" |
| "Low risk / high risk" | "Within typical range / some measures outside typical range / multiple measures outside typical range" |

**Never display a raw model probability.** The number a classifier emits is its confidence on its training distribution, not the user's probability of having a disease. Percentiles against a reference sample are the honest equivalent and are more informative anyway.

**Don't name Parkinson's in the results verdict itself.** It belongs in the explanation of why these measurements were chosen, not in the line that tells the user what happened.

**Don't say early detection saves lives.** There is no disease-modifying treatment yet. Say: *earlier conversations mean earlier symptom management and access to clinical trials.*

---

## TRAINING AND REHABILITATION

| Don't say | Say |
|---|---|
| "Our app improves fine motor control" | "Implements protocols of the kind shown in a randomized controlled trial to improve writing speed and clinician-rated motor scores (Vorasoot et al., 2020)" |
| "Improves motor control" | "Measured writing size increased within the session" |
| "Treats Parkinson's" | "Provides motor exercises intended to support fine-motor function" |
| "Slows progression" | *Nothing. Do not make this claim in any form.* |
| "Replaces LSVT BIG" / "equivalent to clinical therapy" | "Delivers exercises based on the same principles at home" |
| "Ensures improvement retains speed and smoothness" | "If size improves at the cost of speed or smoothness, the system detects it and adjusts the next exercise instead of counting it as progress" |

**The provenance/outcome distinction is the whole game here.** You can say the *technique* has evidence behind it — that's a fact about the literature. You cannot say *your app* produces the outcome — that's a fact about your users, and only your own trial could establish it.

**Within-session change is not improvement.** It is a measurement taken twenty minutes apart. Say "change measured within a single session in N users." Never imply it persists.

---

## MEDICATION

| Don't say | Say |
|---|---|
| "Shows how effective your medication is" | "Shows when your measured performance is strongest relative to your dose timing" |
| "Your dose isn't working" | *Nothing. Never interpret.* |
| Any suggestion about dosage or timing changes | *Nothing, ever. This is practicing medicine.* |

Frame it as an **objective medication diary** — the tool neurologists already ask patients to keep, except measured instead of remembered. That framing is accurate and it's a stronger pitch than "medication tracker."

---

## MONITORING AND CHANGE OVER TIME

| Don't say | Say |
|---|---|
| "Your Parkinson's progressed 12%" | "Your measured motor performance changed 12% relative to your baseline" |
| "Your condition is worsening" | "Writing size decreased relative to your established baseline" |
| "You're getting better" | "Measured smoothness improved relative to your baseline" |

The app measures motor performance. It does not measure disease. Many things move these numbers — caffeine, fatigue, sleep, anxiety, medication timing, cold hands, familiarity with the task — and the results screen should say so.

---

## COMPARISON TO CLINICIANS

| Don't say | Say |
|---|---|
| "More accurate than a neurologist" | "More reproducible than a clinician rating" |
| "Replaces a neurological exam" | "Produces measurements to bring to a neurological exam" |
| "As good as a clinical assessment" | *Nothing.* |

Reproducible and accurate are different properties. Your numbers are identical regardless of who administers them — that's reproducibility, it's real, and it's a genuine advantage over a human rating scale. It says nothing about accuracy.

---

## BIOMARKERS AND OTHER TESTS

Don't imply the app substitutes for a biological test. The real biomarkers — alpha-synuclein seed amplification assays — require a lumbar puncture or a skin biopsy, and they measure something the app cannot.

**Say:** "Objective biomarkers exist but require a spinal tap or skin biopsy. There is no accessible, repeatable, non-invasive motor measurement available outside a clinic."

**On the prodromal criteria:** if you reference the MDS research criteria for prodromal Parkinson's, note that they are explicitly *research* criteria and not intended for telling individuals they have a disease.

---

## MODEL PERFORMANCE

Report ranges, never a single number. A test set of a dozen patients produces an accuracy figure with an enormous confidence interval, and quoting "0.94" from it is not a real claim.

Say which datasets, and say that splits were made by patient rather than by drawing.

**Acknowledge the label ceiling.** Every training label is a clinical diagnosis, and clinical diagnosis runs roughly 80–90% accurate against autopsy even among specialists. Your model converges on agreeing with clinicians, including where they're wrong. State this yourself — it's the cheapest credibility available and almost no competing submission will do it.

**Don't claim the model is validated on phones.** It's trained on clinical tablet data. The degradation experiment *estimates* what that costs; it doesn't validate the phone deployment. Say so.

---

## DEMO AND DATA HONESTY

**Sample data must be visibly labeled as sample data.** Seeding a chart to demonstrate a feature is completely standard. Presenting it as a real user's result is not. Put "sample data" on screen.

**Simulation results must be labeled as simulation.** The optimizer study shows the algorithm converging against a simulated patient. That's a legitimate result and an illegitimate one is the same figure without the word "simulated."

**Narrating a scenario is fine.** "Say I took my medication at 8am — here's what the app shows after a few weeks of use" is honest and it's how anyone demos a feature that accumulates data over time.

**Check the current Challenge rules** for language about representing your app accurately.

---

## THE SENTENCES YOU CAN USE VERBATIM

Tested against everything above. These are safe.

> NeuroTrace turns an ordinary phone into a motor-function measurement tool.

> Machine learning models trained on clinical movement-disorder datasets extract motor features that clinicians look for in Parkinson's disease.

> NeuroTrace reports where each measure falls relative to a reference population and tracks how it changes over time.

> These are measurements of how you moved during the tasks, compared with other people who took the same tasks. They are not a diagnosis and cannot tell you whether you have a neurological condition.

> NeuroTrace's training module implements structured handwriting exercise protocols of the kind shown in a randomized controlled trial to improve writing speed and clinician-rated motor examination scores in people with Parkinson's disease.

> NeuroTrace tracks all four dimensions together. If writing size improves at the cost of speed or smoothness, the system detects it and adjusts the next exercise instead of counting it as progress.

> Amplitude-focused training has been shown to improve writing size while degrading fluency and stroke duration. NeuroTrace measures all four dimensions simultaneously, so that tradeoff is visible rather than hidden.

> The established amplitude-training protocol requires sixteen in-person sessions over four weeks with a certified clinician. NeuroTrace delivers exercises based on the same principles at home.

> Medication diaries rely on recall and subjective rating. NeuroTrace records when a dose was taken and measures motor performance objectively at any point afterward.

> All analysis runs on the device. No motor data ever leaves the phone.

---

## WHY THIS DOCUMENT IS AN ASSET, NOT A CONSTRAINT

Precise claims read as more competent than sweeping ones. "The system detects the tradeoff and adjusts the next exercise" is a thing a judge can watch happen on screen; "ensures improvement" is a thing they have to take on faith and might not.

And a limitations section written in this register is the single cheapest credibility available to you. Almost no competing submission will have one — which means yours stands out for the thing that's hardest to fake.
