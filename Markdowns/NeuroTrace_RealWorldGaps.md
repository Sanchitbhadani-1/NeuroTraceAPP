# Real-World Gaps NeuroTrace Addresses

A running list of documented problems in current Parkinson's care and research, what NeuroTrace does about each, and the exact wording that stays defensible.

Structure your demo and writeup around these: name the gap, show the evidence, then show your response. That order matters — a feature nobody asked for is a feature; a feature that answers a named problem is an argument.

---

## TIER ONE — Strongest. Documented, specific, and directly addressed.

### 1. Existing handwriting therapy trades fluency for size, and doesn't measure the cost

**The gap.** Standard amplitude-focused training tells people to write bigger. It works — writing gets bigger. But a 2018 randomized trial (Nackaerts et al., *PLOS One*, 38 patients, six weeks) found that stroke duration and fluency got measurably *worse* over the same period, while a comparison group doing stretching showed the opposite pattern. The motor system appears to reallocate toward size at the expense of smoothness. A therapist watching someone write cannot see this happening; they can see the letters got bigger.

**What NeuroTrace does.** Measures size, speed, smoothness, and accuracy simultaneously, before and after every exercise, and shows all four together — so improving one at the expense of another becomes visible rather than invisible.

**Wording that holds.** "Amplitude-focused training has been shown to improve writing size while degrading fluency and stroke duration. NeuroTrace measures all four dimensions simultaneously, so that tradeoff is visible rather than hidden."

**This is your single best gap.** It is documented, specific, nobody else will have it, and your response to it is the most original thing you've designed.

---

### 2. The therapy that works requires sixteen in-person visits in a month

**The gap.** LSVT BIG — the established, certified amplitude-training protocol — is delivered at a fixed minimum dose: sixteen one-hour individual sessions, four days a week for four consecutive weeks, with a certified clinician, plus daily homework and carryover assignments every day of the month. There is no reduced version.

Consider who has to do this. Someone with a movement disorder, often elderly, possibly no longer driving, needs to physically get to a clinic sixteen times in thirty days, and needs a certified provider to exist near them.

**What NeuroTrace does.** Delivers exercises built on the same principles — amplitude targets, cueing, structured progression — on a phone the person already owns, at home, for free.

**Wording that holds.** "The established amplitude-training protocol requires sixteen in-person sessions over four weeks with a certified clinician. NeuroTrace delivers exercises based on the same principles at home."

**Do not say** it replaces LSVT BIG, or that it is equivalent to it. You have not tested that and it is a much bigger claim.

---

### 3. The intervention that worked in the trial was a paper book with no feedback

**The gap.** The randomized trial you found (Vorasoot et al., 2020) used a purpose-built handwriting practice book. It worked — writing speed improved 16.2% and the clinician-rated motor exam improved. But a book cannot tell you whether you're doing it right, cannot adjust to your specific deficit, and gives every patient the same pages regardless of what is actually wrong with their movement.

**What NeuroTrace does.** Measures every stroke, routes you to the exercise addressing your largest measured deficit, and cues in real time.

**Wording that holds.** "The trial's intervention was a printed practice book identical for every participant. NeuroTrace delivers the same category of exercise with per-stroke measurement, real-time cueing, and exercise selection driven by the individual's measured deficit."

---

### 4. Medication diaries depend on memory and self-rating

**The gap.** Parkinson's symptoms fluctuate through the day around medication timing — the on-off pattern. To adjust dosing schedules, neurologists ask patients to keep medication diaries. Those diaries are built from recall and subjective self-assessment, recorded hours after the fact. "Felt pretty good around lunch, I think."

**What NeuroTrace does.** A timestamped medication log plus a twenty-second objective motor measurement the person can take at any point in the day. The result is an objective version of a tool clinicians already use.

**Wording that holds.** "Medication diaries rely on recall and subjective rating. NeuroTrace records when a dose was taken and measures motor performance objectively at any point afterward, producing a timing profile rather than a recollection."

**Do not say** the app shows how effective the medication is, or suggest any dosage change. What it shows is *when measured performance is strongest relative to dose timing*.

---

### 5. Nothing measures anything between appointments

**The gap.** A person with Parkinson's typically sees their neurologist a small number of times per year. At each visit, months of day-to-day and hour-to-hour variation get compressed into whatever the patient can remember and articulate — usually something like "I think my hand has gotten worse recently." The visit itself is one snapshot, at one time of day, usually when medication is working.

**What NeuroTrace does.** A two-minute measurement the person can take weekly at home, producing a continuous record instead of two data points a year.

**Wording that holds.** "Between appointments, no motor measurement happens at all. NeuroTrace produces a weekly objective record, so the conversation starts from data instead of recollection."

---

### 6. There is no personal baseline in clinical care

**The gap.** Everyone's handwriting and fine-motor performance differ enormously at baseline. Some people always wrote small, always wrote fast, always wrote messily. A clinician meeting you for the first time has no idea what your handwriting looked like three years ago, and neither does any medical record. So the most informative comparison — you against your former self — is unavailable to everyone.

**What NeuroTrace does.** Establishes a personal baseline after three assessments and reports change relative to it.

**Wording that holds.** "No clinical record contains a person's handwriting from three years ago, so the most informative comparison — the person against their own history — is unavailable in standard care. NeuroTrace builds that baseline from the person's first assessments."

**This is also your answer to the obvious objection** that everyone's handwriting is naturally different. Worth having ready.

---

### 7. Clinical motor scoring is a human judgment call

**The gap.** The standard motor examination (MDS-UPDRS Part III) is scored by a clinician watching the patient. It's the accepted instrument, but it is a rating, not a measurement — and inter-rater variability between different examiners is a documented, studied problem.

**What NeuroTrace does.** Produces numbers that are identical regardless of who is in the room.

**Wording that holds.** "The standard motor exam is a clinician's rating, with known variability between examiners. Digital motor measurement produces the same number regardless of who administers it."

**Do not say** it is more accurate than a neurologist. It is more *reproducible*. Those are different, and the distinction is the whole point.

---

## TIER TWO — Real gaps, addressed partially or as research contributions

### 8. Parkinson's and essential tremor are routinely confused

**The gap.** Essential tremor is far more common than Parkinson's and the two get mistaken for each other, particularly early. Even the specialist imaging test (DaTscan) only separates degenerative parkinsonism from non-degenerative causes — it cannot distinguish Parkinson's from atypical parkinsonian syndromes.

**What NeuroTrace does.** Attempts the differential using the smartwatch dataset, which contains essential tremor, atypical parkinsonism, and healthy controls. The distinguishing signals are spectral (Parkinsonian rest tremor sits around 4–6 Hz and attenuates with movement; essential tremor sits higher and worsens with action) and asymmetric (Parkinson's is typically one-sided; essential tremor is usually more symmetric).

**Frame this as a research result, not a product feature.** "We tested whether the same measurements separate Parkinson's from other tremor disorders, which is a substantially harder problem than separating it from healthy controls."

---

### 9. Prodromal criteria require a clinician to score the motor component

**The gap.** There is a published framework — the MDS research criteria for prodromal Parkinson's — that combines markers with likelihood ratios to estimate probability. One of its inputs is "subthreshold parkinsonism," meaning motor signs below the diagnostic threshold. Scoring it requires a clinical examination, which means the framework can't be applied outside a clinic.

**What NeuroTrace could do.** Supply a quantitative, at-home version of that motor input.

**Frame as a future direction, clearly.** These are research criteria and explicitly not intended for telling individuals they have a disease.

---

### 10. There is no accessible objective motor measurement

**The gap.** The genuine biomarkers that have emerged — alpha-synuclein seed amplification assays — work well, and require a lumbar puncture or a skin biopsy. There is no non-invasive, low-cost, repeatable objective measure of Parkinsonian motor function available to an ordinary person.

**Wording that holds.** "Objective biomarkers for Parkinson's now exist but require a spinal tap or a skin biopsy. There is no accessible, repeatable, non-invasive motor measurement available outside a clinic."

**Do not imply** the app substitutes for a biomarker. It measures motor signs, which is a different thing.

---

## TIER THREE — Gaps in the research literature (strong for the writeup, weaker for video)

### 11. Published digital Parkinson's models are trained on clinical tablets and nobody has measured what happens on a phone

Every major handwriting dataset was collected on a graphics tablet with a digital pen at high sampling rates, capturing pressure and tilt. Consumer phones capture none of that. No published work quantifies how much accuracy is lost across that gap. Your degradation experiment does exactly this, and it is likely the most original technical contribution in the project.

### 12. Published accuracy figures are frequently inflated by patient leakage

Many studies split data by *drawing* rather than by *person*, so the same patient appears in both training and testing. The model learns to recognize the individual, not the disease. Patient-level splitting is why your numbers will look lower than published ones — and why they'll be real.

### 13. No model can exceed the accuracy of the labels it was trained on

Every dataset label is a clinical diagnosis, and clinical diagnosis of Parkinson's runs roughly 80–90% accurate against autopsy even among specialists. A model trained on those labels converges on agreeing with clinicians, including where clinicians are wrong. Any project claiming 97% diagnostic accuracy is really reporting 97% agreement with imperfect labels on an easy dataset.

**This belongs in your limitations section.** Stating it yourself is the cheapest credibility available to you.

---

## HOW TO USE THIS IN THE DEMO

You cannot fit thirteen gaps into three minutes. Pick three, and make each one a beat: *here is a real problem → here is what NeuroTrace does → here is it working.*

The three that carry the most weight per second:

**The tradeoff (gap 1)** — most original, documented, and your response to it is unique. Roughly: "The standard therapy makes handwriting bigger. A 2018 trial found it also makes it slower and less fluent. Nobody was measuring that, because you can't see it by watching. NeuroTrace measures four things at once."

**Sixteen visits (gap 2)** — instantly understandable, emotionally legible, and the contrast with a phone is self-evident.

**The diary (gap 4) or the appointment interval (gap 5)** — both make the same point about memory versus measurement. Pick whichever fits your footage.

Save gaps 11 through 13 for the written submission, where a reader has time and where honesty about limitations reads as sophistication rather than as hedging in a video.

---

## SOURCES

- Nackaerts et al., *Handwriting training in Parkinson's disease: a trade-off between size, speed and fluency*, PLOS One, 2018
- Vorasoot et al., *Effects of handwriting exercise on functional outcome in Parkinson disease: a randomized controlled trial*, Journal of Clinical Neuroscience, 2020 — and the published Letter to the Editor responding to it
- LSVT Global, protocol dosage documentation
- MDS research criteria for prodromal Parkinson's disease (Heinzel et al., 2019 update)
- Alpha-synuclein seed amplification assay literature (CSF and skin biopsy)
- Inter-rater variability studies on the MDS-UPDRS Part III
- 2023 scoping review of rehabilitative interventions for impaired handwriting in Parkinson's
