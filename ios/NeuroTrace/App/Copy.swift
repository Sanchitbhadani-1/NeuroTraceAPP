import Foundation

enum Copy {

    struct Tier {
        var label: String
        var meaning: [String]
        var todo: String
    }

    struct Measure {
        var name: String
        var group: String
        var hi: String
        var lo: String
    }

    struct Group {
        var id: String
        var title: String
        var desc: String
    }

    struct AgeChoice {
        var label: String
        var bracket: String?
    }

    private static func num(_ x: Double) -> String { jsNumberString(x) }

    static let notADiagnosis =
        "These are measurements of how you moved during the tasks, compared with other people who " +
        "took the same tasks. They are not a diagnosis and cannot tell you whether you have a " +
        "neurological condition."

    private static let manyThings =
        "Many things move these numbers — caffeine, fatigue, sleep, anxiety, medication timing, cold " +
        "hands, familiarity with the task. One drawing is a single reading, not a pattern."

    static let manyThingsShort = manyThings.firstIndex(of: ".").map { String(manyThings[...$0]) } ?? ""

    // Picked by where the combined result falls among the healthy reference group. Below 75%, 75% to 95%,
    // or 95% and up (Score.tierCuts)
    static let tiers = [
        Tier(
            label: "Within the typical range",
            meaning: [notADiagnosis],
            todo:
                "Draw the spiral again on another day if you want to see how much your own numbers move " +
                "between sittings. Your own baseline is the comparison that means the most over time."
        ),
        Tier(
            label: "Above the typical range",
            meaning: [notADiagnosis, manyThings],
            todo:
                "Draw the spiral again over the next few days. A result that keeps landing above the " +
                "typical range tells you more than one that did it once."
        ),
        Tier(
            label: "Well above the typical range",
            meaning: [notADiagnosis, manyThings],
            todo:
                "Check in again on another day, since one reading can be thrown off by many things. If you have " +
                "already noticed a change in how you move, these measurements are something concrete to bring " +
                "to a doctor."
        ),
    ]

    static let tierShort = ["Typical", "Above", "Well above"]

    static let measures: [String: Measure] = [
        "spiral_duration": Measure(name: "Drawing time", group: "speed", hi: "Took longer than", lo: "Quicker than"),
        "spiral_max_deviation": Measure(name: "Largest wobble", group: "shape", hi: "Larger than", lo: "Smaller than"),
        "spiral_mean_deviation": Measure(name: "Average wobble", group: "shape", hi: "Larger than", lo: "Smaller than"),
        "spiral_std_deviation": Measure(name: "Wobble variation", group: "shape", hi: "More varied than", lo: "Steadier than"),
        "spiral_major_reversals": Measure(name: "Course corrections", group: "shape", hi: "More frequent than", lo: "Less frequent than"),
        "spiral_mean_speed": Measure(name: "Average speed", group: "speed", hi: "Faster than", lo: "Slower than"),
        "spiral_std_speed": Measure(name: "Speed variation", group: "speed", hi: "More varied than", lo: "Steadier than"),
        "spiral_ldlj": Measure(name: "Smoothness", group: "smoothness", hi: "Smoother than", lo: "Less smooth than"),
        "spiral_sparc": Measure(name: "Smoothness, second method", group: "smoothness", hi: "Smoother than", lo: "Less smooth than"),
        "spiral_tremor_4_6": Measure(name: "Tremor, 4–6 Hz", group: "tremor", hi: "Stronger than", lo: "Weaker than"),
        "spiral_tremor_6_12": Measure(name: "Tremor, 6–12 Hz", group: "tremor", hi: "Stronger than", lo: "Weaker than"),
        "spiral_tremor_dominant_hz": Measure(name: "Main wobble frequency", group: "tremor", hi: "Higher than", lo: "Lower than"),
    ]

    static let groups = [
        Group(id: "shape", title: "Shape", desc: "How closely your line followed a smooth spiral fitted to your own drawing."),
        Group(id: "speed", title: "Speed", desc: "How fast you drew, and how evenly."),
        Group(id: "smoothness", title: "Smoothness", desc: "How fluid the movement was, by two standard methods."),
        Group(id: "tremor", title: "Tremor", desc: "Small, fast, rhythmic wobble in the line."),
    ]

    static func measureSentence(_ key: String, _ frac: Double) -> String {
        let hi = measures[key]!.hi, lo = measures[key]!.lo
        let p = jsRound(frac * 100)
        return p >= 50 ? "\(hi) \(num(p))% of the reference group" : "\(lo) \(num(100 - p))% of the reference group"
    }

    // The same, short enough for a table cell in the doctor summary
    static func measureShort(_ key: String, _ frac: Double) -> String {
        guard let m = measures[key], frac.isFinite else { return "–" }
        let p = jsRound(frac * 100)
        return p >= 50 ? "\(m.hi) \(num(p))%" : "\(m.lo) \(num(100 - p))%"
    }

    private static let agePhrase = [
        "all": "of all ages",
        "50s": "aged under 60",
        "60s": "aged 60 to 69",
        "70s": "aged 70 to 79",
        "80+": "aged 80 and over",
    ]

    static func referenceSentence(referenceN: Int, bracketKey: String, deviceMatched: Bool) -> String {
        let ages = agePhrase[bracketKey].map { phrase in " " + phrase } ?? ""
        let base = "Compared with \(referenceN) healthy adults\(ages)."
        let device = deviceMatched
            ? " They drew on this kind of device."
            : " They drew on a different kind of device, so small differences may come from the device rather than from you."
        return base + device
    }

    static let ageChoices = [
        AgeChoice(label: "Under 60", bracket: "50s"),
        AgeChoice(label: "60–69", bracket: "60s"),
        AgeChoice(label: "70–79", bracket: "70s"),
        AgeChoice(label: "80 or over", bracket: "80+"),
        AgeChoice(label: "Prefer not to say", bracket: nil),
    ]

    static let pitch = "NeuroTrace turns an ordinary iPad into a motor-function measurement tool."
    static let tracks = "It reports where each measure falls relative to a reference population and tracks how it changes over time."
    static let onDevice = "All analysis runs on this device. Your data only leaves it if you choose to share it."

    static let consentUnderstand = "I understand this is a measurement tool, not a medical diagnosis."
    static let consentAdult = "I am 18 years of age or older."
    static let consentHelp = "Check both boxes to continue."
    static let aboutWhy = "Used only to choose who you are compared with. Kept on this device."
    static let handHelp =
        "The hand you will draw with. Use the same one each time so your check-ins compare fairly. To compare your two hands, do one check-in with each."
    static let checkinBlurb = "About two minutes. Trace three spirals with your finger or an Apple Pencil."
    static let historyEmpty = "Your results will appear here after your first check-in. They stay on this device."
    static func drawInstruction(_ hand: String?) -> String {
        let which = hand == "left" || hand == "right" ? "Use your \(hand ?? "") hand. " : ""
        return which + "Start at the dot in the middle and follow the gray line outward, at a comfortable pace. " +
            "Lifting your pen or finger is fine. Keep going from where you stopped."
    }
    static let tooShort =
        "That spiral was too short to measure. Please draw the whole spiral, from the middle to the outside."
    static let spiralOffGuide =
        "That didn't follow the spiral closely enough to measure. Start at the dot in the middle and trace along the " +
        "gray line, all the way out."
    static let spiralTooFast =
        "That was too quick to measure. Please trace the spiral again at a comfortable pace, from the middle " +
        "to the outside."
    static let spiralStillOff =
        "This spiral still couldn't be measured. Take as long as you need, start at the dot in the middle and stay close " +
        "to the gray line. You can also tap Cancel and try another time."
    static let collectIntro =
        "Three spirals per participant, for the device-matched reference. No results are calculated or " +
        "shown in this mode."
    static let newParticipant =
        "A random ID is made for them. Write it on their signed consent form — names are never stored."
    static let returningBlurb = "Pick up an ID already on this iPad."
    static let collectDrawInstruction =
        "Start at the dot in the middle and trace outward at a comfortable pace. Lifting the pencil is " +
        "fine — keep going from where you stopped."
    static let sessionSaved =
        "Three spirals are stored on this iPad. Thank the participant — no results are shown in collection mode."

    static let nothingScored = "Nothing was scored."
    static let resizeCleared = "The screen changed size, so this spiral was cleared. Please draw it again."

    static let stoodOutCaption = "The measures that pushed your combined result up the most."
    static let nothingPushedUp = "No measure pushed your combined result up this time."

    static let modelCardCaption =
        "All twelve measures go into one model, which weighs each of them and combines them into a single result."

    static func modelScoreSentence(referenceN: Int) -> String {
        "of the \(referenceN) healthy adults in the reference group had a lower combined result than yours."
    }

    static let contribCaption =
        "How far each measure moved your combined result, biggest first. A short bar means that measure barely mattered."
    static let contribRaised = "raised your result"
    static let contribLowered = "lowered your result"

    // The one place to change the number: the per-fold AUC that training/scripts/plot_cv_scores.py prints.
    // The disclaimer below is built from it, so it can't drift
    static let modelAUC = 0.71

    // The gray line under the big number. Deliberately not a percentage: the big number above it already
    // is one, and two different percentages stacked together read as one claim
    static var modelDisclaimer: String {
        let auc = String(format: "%.2f", modelAUC)
        let outOfTen = Int((modelAUC * 10).rounded())
        return "Not a diagnosis. Shown drawings from one person with Parkinson's and one without, made on research " +
            "tablets, this model ranks them correctly about \(outOfTen) times in 10 (AUC \(auc), where a coin flip " +
            "would be 0.50)."
    }

    static let modelNote =
        "The model is a logistic regression trained on spiral drawings from 112 people, with and without " +
        "Parkinson's, from two research datasets drawn with a pen on digitizing tablets, not on iPads. Its AUC was " +
        "measured only on people it hadn't seen during training."
    // Only true while the reference group is the research stand-in, not drawings made on iPads
    static let referenceInTraining = "The healthy adults in the reference group were among the people it was trained on."

    static let everyMeasureCaption =
        "Each dot shows where you sit among the reference group. The mark in the middle is the halfway point."
    static let rawLegend = "What the screen recorded."
    static let filteredLegend =
        "The same line smoothed (100 Hz, 15 Hz low-pass) — the version every measure is taken from."
    static let speedCaption = "From your first touch on the left to your last on the right."
    static let drawingPruned =
        "A lighter copy of your drawing. The full recording, with the smoothed line and the speed chart, is kept " +
        "for your three most recent check-ins."
    static let resultSummary = "This is a measurement of how you drew today, not a diagnosis."

    static let settingsDetailsHelp = "Used to choose who you are compared with. Changes apply to your next check-in."
    static let appearanceHelp = "Automatic follows your device's setting."
    static let deleteHelp =
        "Removes everything NeuroTrace saved about you on this device: your age group and drawing hand, check-ins, " +
        "practice, medication and doses, finger tapping tests and home scans. Collection mode's research sessions " +
        "stay. This can't be undone."
    static let deleteConfirm = "Delete all your data from this device?"
    static let deleteConfirmDetail = "This can't be undone."
    static let deleted = "All your data was deleted."
    static let deleteFailed = "Couldn't delete everything. Try again."
    static let summaryBlurb =
        "One PDF with your check-ins, finger tapping, medication and practice, to print or share before a doctor's visit."
    static let summaryShared = "Summary shared"
    static let summaryEmpty = "Do a check-in or a finger tapping test first, so the summary has something in it."
    static let collectionHelp = "For the research team. Records spirals for the reference group and never shows results."
    static let howSteps = [
        "Trace a spiral on the screen with your finger or an Apple Pencil.",
        "NeuroTrace measures 12 things about the line: its shape, speed, smoothness and tremor.",
        "A machine-learning model, trained on spiral drawings from 112 people with and without Parkinson's, combines all 12 into one result.",
        "Each measure is placed among a reference group of healthy adults.",
    ]
    static let credit = "Made by Sanchit Bhadani, Aryan Modi, and Mihir Malladi for the 2026 Congressional App Challenge."

    static let loginNote = "Accounts aren't set up yet. For now, logging in opens the app on this device."
    static let logoutHelp = "Accounts aren't set up yet. Logging out takes you back to the welcome screen. Your check-ins stay on this device."

    // Sample data for demo videos. Only in builds run from Xcode
    static let sampleHelp = "For demo videos. Replaces what's on this device with about three weeks of made-up check-ins, doses, practice and finger tapping. It can take a minute or so to make."
    static let sampleConfirm = "Replace your data with sample data?"
    static let sampleConfirmDetail = "Your check-ins, doses, practice and finger tapping on this device are replaced with made-up ones. This can't be undone."
    static let sampleLoading = "Making sample data\u{2026}"
    static let sampleLoaded = "Sample data loaded"
    static let sampleFailed = "Couldn't load the sample data"

    // Accounts, with Firebase. An account only signs someone in
    static let accountNote = "Log in or create an account with your email. Your check-ins stay on this device."
    static let accountLogInLede = "Welcome back. Log in with the email you signed up with."
    static let accountCreateLede = "All you need is an email and a password, with at least 6 characters."
    static let accountPrivacy = "Signing in is handled by Google's Firebase. Your check-ins, drawings and medication stay on this device."
    static let accountBadEmail = "That email doesn't look right. Check it and try again."
    static let accountTaken = "There's already an account with that email. Log in instead."
    static let accountWeakPassword = "That password is too short. Use at least 6 characters."
    static let accountWrong = "That email and password don't match. Try again, or tap Forgot password."
    static let accountOffline = "Couldn't connect. Make sure you're online, then try again."
    static let accountTooMany = "Too many tries. Wait a few minutes, then try again."
    static let accountRecentLogin = "For your safety, log out and log back in, then delete your account."
    static let accountDisabled = "This account has been turned off."
    static let accountNotTurnedOn = "Email accounts aren't turned on for this app yet."
    static let accountFailed = "Something went wrong. Try again."
    static let accountNeedEmail = "Type your email above first, then tap Forgot password."
    static func accountResetSent(_ email: String) -> String {
        "Check your email. If there's an account for \(email), a link to reset the password is on its way."
    }
    static func signedInAs(_ email: String) -> String { "Signed in as \(email)" }
    static let accountLogoutHelp = "Logging out takes you back to the welcome screen. Your check-ins stay on this device."
    static let accountDeleteConfirm = "Delete your account?"
    static let accountDeleteDetail = "You won't be able to log in with it again. Your check-ins stay on this device until you use Delete all my data."
    static let accountDeleted = "Account deleted"
    static let testingBlurb =
        "Short tests that measure how you move. Use the same hand on the same device each time, so your results compare fairly."

    // Finger tapping, from Aryan's tapping test
    static let tapBlurb = "Tap your index finger and thumb together in front of the camera. It takes about 15 seconds."
    static let tapTips = "Prop the iPad up, sit about an arm's length away, palm facing the camera, in good light."
    static let tapGo = "Tap your index finger and thumb together, as fast and as wide as you can."
    static let tapNoCamera = "NeuroTrace can't use the camera. You can allow it in Settings."
    static let tapNoFrontCamera = "This device has no front camera NeuroTrace can use, so the tapping test can't run here."
    // For iPads too old for Apple's hand tracking, like iPad (7th generation)
    static let tapOldIPadTitle = "This iPad may be too old for finger tapping"
    static let tapOldIPad = "Apple's hand tracking doesn't run well enough on older iPads to count taps. It needs iPad (8th generation), " +
        "iPad Air (3rd generation), iPad mini (5th generation), iPad Pro (2018) or newer."
    static let tapTooFew = "Fewer than 5 taps were found. Try again with your whole hand in view and good light."
    static let tapTooSlow =
        "The camera couldn't follow your hand quickly enough to count taps, so this test wasn't kept. Try again in " +
        "brighter light, with other apps closed."
    static let tapNotDiagnosis = "This is a measurement of how you tapped today, not a diagnosis."
    static func tapLooksLike(_ seen: String) -> String { "That looks like your \(seen) hand" }
    static func tapWrongHand(_ seen: String, _ picked: String) -> String {
        "That looked like your \(seen) hand, but the \(picked) hand was picked, so this test wasn't saved. Pick the hand " +
            "you're using and try again."
    }
    static let tapOnDevice = "The camera picture stays on this iPad and is never saved. Only the numbers are kept."

    // previous: this hand's earlier counted tries, newest first
    static func tapSentences(_ r: TapResult, previous: [TapResult]) -> [String] {
        guard r.counted, let duration = r.duration, let rate = r.rate else { return [tapTooFew] }
        var out = ["\(r.taps) taps in \(String(format: "%.1f", duration)) seconds: \(String(format: "%.1f", rate)) taps per second."]
        if let change = r.openingChange {
            let pct = Int((abs(change) * 100).rounded())
            out.append(pct < 10
                ? "Your finger opening stayed about the same size."
                : "Your finger opening got \(pct)% \(change < 0 ? "smaller" : "larger") from your first taps to your last.")
        }
        if r.pauses > 0 {
            out.append("\(r.pauses) \(r.pauses == 1 ? "pause that was" : "pauses that were") longer than your usual rhythm.")
        }
        let rates = previous.compactMap { p in p.rate }.prefix(3)
        if !rates.isEmpty {
            let ratio = rate / (rates.reduce(0, +) / Double(rates.count))
            let word = ratio > 1.1 ? "faster" : ratio < 0.9 ? "slower" : "about the same"
            out.append("Compared with your last \(rates.count == 1 ? "try" : "\(rates.count) tries") with this hand: \(word).")
        }
        return out
    }

    // What VoiceOver reads for the finger opening chart
    static func tapChartLabel(_ r: TapResult) -> String {
        guard let first = r.openings.first, let last = r.openings.last else { return "Finger opening at each tap" }
        return "Finger opening at each of \(r.openings.count) taps, from \(String(format: "%.2f", first)) at the first tap to \(String(format: "%.2f", last)) at the last"
    }

    // Home safety scan, from Aryan's home scan
    static let scanBlurb = "Take a photo of a room and get ideas from common home-safety checklists."
    static let careBlurb = "Your medication, a summary for your doctor, and ideas to make your home easier to move around in."
    static let practicedToday = "You've already practiced today. Another try is fine whenever you feel like it."
    static let scanHow = "Stand in the doorway and fit as much of the floor and furniture in the photo as you can."
    static let scanPrivateAI = "Your photo is sent to Google's Gemini AI to get the ideas. NeuroTrace doesn't keep the photo."
    static let scanConsent = "Your photo is sent to Google's Gemini AI to get the ideas. NeuroTrace doesn't keep the photo. Don't include people, faces or private papers."
    static let scanOffline = "Gemini couldn't be reached, so this photo wasn't checked. Make sure you're online, then try again."
    static let scanPhotoNote = "This is the photo Gemini looked at. It's only shown here, and NeuroTrace doesn't save it."
    static let scanNotSetUp = "The home scan isn't available. It needs Gemini, which isn't set up in this copy of NeuroTrace."
    static let scanLooking = "Looking at your photo…"
    static let scanNotRoom = "That doesn't look like a room. Try a photo that shows the floor and furniture."
    static let scanEmpty = "No ideas came from this photo. Try a wider photo of the room."
    static let scanUnreadable = "That photo couldn't be read. Try another one."
    static let scanFooter = "Ideas from common home-safety checklists. Not a professional safety check."
    static let medBlurb = "The medicines you take, with the dose and when you take them."
    static let medCardBlurb =
        "Log each dose as you take it. After a few check-ins, NeuroTrace shows how your drawing changes in the hours after a dose."
    static let medLede =
        "Log your doses here. Each check-in is matched to the dose before it, to show when your drawing tends to be at its best."
    static let noDoses = "No doses logged yet."
    static let doseLogged = "Dose logged"
    static let doseTwice = "Dose already logged"
    static let doseNotSaved = "Couldn't save the dose"
    static let doseNotRemoved = "Couldn't remove the dose"
    static let logDoseHelp = "Forgot to log one? Set the time you took it."
    static let removeDoseConfirm = "Remove this dose?"
    static func recentDoses(_ shown: Int) -> String { "Your \(shown) most recent doses." }
    static let timingCaption = "Each check-in is grouped by how long after a dose you drew it. Longer bars mean better drawing."
    static let timingHowTo =
        "Only check-ins within 12 hours of a logged dose count. Check in at different times after a dose, " +
        "with the same hand and the same pen or finger."
    static let timingCaution =
        "This shows a pattern in your drawing, not how well your medicine works. Don't change when you take " +
        "your medicine without talking to your doctor."
    static let timingLabels = ["spiral_mean_speed": "Speed", "spiral_ldlj": "Smoothness", "spiral_mean_deviation": "Wobble", "spiral_tremor_4_6": "Tremor"]
    static let timingSpread = "No time window has two check-ins in it yet. Try checking in twice at about the same time after a dose."
    static func timingSoFar(_ n: Int) -> String { "\(min(n, Meds.minCheckins)) of \(Meds.minCheckins) check-ins so far" }
    static func hoursAfter(_ from: Double, _ to: Double) -> String { "\(num(from)) to \(num(to)) \(to == 1 ? "hour" : "hours")" }
    static func bestTime(_ from: Double, _ to: Double) -> String { "So far, best \(hoursAfter(from, to)) after a dose" }
    static func checkinCount(_ n: Int) -> String { n == 0 ? "No check-ins" : n == 1 ? "1 check-in" : "\(n) check-ins" }
    static func betterThan(_ better: Double) -> String { "Better than \(num(jsRound(better * 100)))% of the reference group" }
    static func bestDetail(_ key: String, _ better: Double, _ n: Int) -> String {
        "In that window, your \((timingLabels[key] ?? "drawing").lowercased()) was typically better than \(num(jsRound(better * 100)))% " +
        "of the reference group, going by \(checkinCount(n).lowercased())."
    }

    static let trainingBlurb = "Short practice exercises. Each one gets a little harder once you've mastered its current level."
    static func trainingWhy(_ measure: String, _ when: String) -> String {
        "Why this one: \(lowerFirst(measures[measure]?.name ?? measure)) stood out most in your \(when) check-in."
    }
    // Only the first letter, so names like "Tremor, 4–6 Hz" keep their Hz
    private static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
    static let focusNothingStoodOut =
        "Nothing in your latest check-in points to one exercise, so this is the one you practiced least recently."
    static let focusNoCheckin =
        "Do a spiral check-in and NeuroTrace will pick the exercise that fits your results. Until then, it's the one you practiced least recently."
    static func weekCount(_ practiced: Int, _ soFar: Int) -> String { "\(practiced) of \(soFar) \(soFar == 1 ? "day" : "days") so far" }
    static func weekSpoken(_ practiced: Int, _ soFar: Int) -> String {
        practiced == 0 ? "No practice yet this week" : "Practiced on \(practiced) of the \(soFar) \(soFar == 1 ? "day" : "days") so far this week"
    }

    static let exerciseNames = [
        "big-writing": "Big writing", "rhythm": "Rhythm", "steady-tracing": "Steady tracing", "hand-skills": "Hand skills",
    ]
    static let instructions = [
        "big-writing": "Write a row of tall loops, like a cursive l, from left to right. Make each loop touch the dashed line.",
        "steady-tracing":
            "Watch the dot trace the spiral, picture yourself drawing it, then trace it yourself from the middle out. " +
            "At higher levels the guide gets fainter.",
        "rhythm": "Turn your sound on. After three clicks, a dot moves along the wave, one stroke per click. Keep your pen with the dot.",
        "hand-skills": "Circles appear one at a time and shrink away. Tap each one before it disappears.",
    ]
    static let padLabels = [
        "big-writing": "Writing area with a baseline and a dashed target line",
        "steady-tracing": "Tracing area with a spiral guide",
        "rhythm": "Tracing area with a wave and a dot to follow",
    ]
    static let watch = "Watch the dot trace the spiral."
    static let look = "Look at the spiral, from the middle out."
    static func imagine(_ n: Int) -> String { "Now picture yourself drawing it. \(n)" }
    static let traceNow = "Your turn. Trace it from the middle out."
    static let rhythmReady = "Tap Start, then put your pen on the dot before it moves."
    static func getReady(_ n: Int) -> String { "Get ready. \(n)" }
    static let follow = "Follow the dot."
    static let rhythmEnd = "That's the end of the wave. Tap Done."
    static let targetsReady = "Tap Start when you're ready."
    static func circleOf(_ n: Int, _ of: Int) -> String { "Circle \(n) of \(of)" }
    static let traceTooShort = "Too little of the spiral to count. Trace it from the middle all the way out."
    static let rhythmTooShort = "Too little of the wave to count. Follow the dot all the way to the end."
    static let comingSoon = "Coming soon"
    static let notStarted = "Not started"
    static let lastChange = ["up": "Went up last time", "down": "Went down last time"]
    static func levelShort(_ n: Int) -> String { "Level \(n)" }
    static func levelOf(_ n: Int, _ of: Int) -> String { "Level \(n) of \(of)" }
    static func hitsSoFar(_ hits: Int, _ need: Int) -> String { "Hits at this level: \(hits) of \(need)" }
    static func missesInARow(_ misses: Int, _ limit: Int) -> String { "Misses in a row: \(misses) of \(limit)" }
    static let topLevel = "Top level. Keep practicing to hold it."
    static let targetLabel = "Reach this line"
    static let tooFewLoops = "Too few loops to count. Write at least 4 tall loops across the row."
    static let verdictHit = "Hit"
    static let verdictMiss = "Not yet"
    static let verdictNotCounted = [
        "big-writing": "Reached the line, but not counted",
        "steady-tracing": "Accurate, but not counted",
        "rhythm": "On the beat, but not counted",
    ]
    static let slowerNotes = [
        "big-writing": "Your pace dropped compared with your recent tries. Keep your usual rhythm as you write bigger.",
        "steady-tracing": "Your pace dropped compared with your recent tries. Keep your usual pace as the guide fades.",
    ]
    static let shakierNotes = [
        "big-writing": "Your writing was less smooth than in your recent tries. Keep the loops smooth as you write bigger.",
        "steady-tracing": "Your line was less smooth than in your recent tries. Keep it smooth as the guide fades.",
        "rhythm": "Your line was less smooth than in your recent tries. Keep it smooth as you follow the dot.",
    ]
    static let measureNames = [
        "size": "Size", "accuracy": "Accuracy", "pace": "Pace", "smoothness": "Smoothness", "coverage": "How much you traced",
        "timing": "Keeping up", "caught": "Caught", "reaction": "Speed", "extra": "Extra taps",
    ]
    private static func pct(_ x: Double) -> Double { jsRound(abs(x) * 100) }
    private static func dontCount(_ n: Double) -> String { n == 1 ? "it doesn't" : "they don't" }
    static func reachedLine(_ reached: Double, _ loops: Double, _ open: Double = 0, _ below: Double = 0) -> String {
        let kind = (open != 0 && !open.isNaN) || (below != 0 && !below.isNaN) ? "letters" : "loops"
        var message = "\(num(reached)) of \(num(loops)) \(kind) reached the line."

        if open != 0 && !open.isNaN {
            let shape = open == 1 ? "was a spike or bump" : "were spikes or bumps"
            let loop = open == 1 ? "a loop" : "loops"
            message += " \(num(open)) \(shape), not \(loop), so \(dontCount(open)) count."
        }

        if below != 0 && !below.isNaN {
            message += " \(num(below)) started or ended well below the baseline, so \(dontCount(below)) count."
        }

        return message + " Filled dots on your writing mark the ones that reached it."
    }
    static let practiceExportHelp = "Saves every practice try on this device as one file, to help tune the exercises."
    static let noPractice = "No practice tries on this device yet"
    static func sizeSentence(_ size: Double, _ shrink: Double) -> String {
        "Your loops averaged \(num(pct(size)))% of the target height." +
            (shrink.isFinite && abs(shrink) >= 0.05
                ? " The last loops in the row were \(num(pct(shrink)))% \(shrink < 0 ? "smaller" : "bigger") than the first."
                : "")
    }
    static func paceSentence(_ pace: Double, _ vs: Double?) -> String {
        "\(toFixed(pace, 1)) loops a second" +
            (vs == nil ? ". Nothing to compare with yet."
                : abs(vs!) < 0.05 ? ", about the same as your recent tries."
                : ", \(num(pct(vs!)))% \(vs! > 0 ? "faster" : "slower") than your recent tries.")
    }
    static func smoothSentence(_ vs: Double?) -> String {
        vs == nil ? "Nothing to compare with yet."
            : abs(vs!) < 0.05 ? "About as smooth as your recent tries."
            : vs! > 0 ? "Smoother than your recent tries." : "Less smooth than your recent tries."
    }
    static func paceVs(_ vs: Double?) -> String {
        vs == nil ? "Nothing to compare with yet."
            : abs(vs!) < 0.05 ? "About the same pace as your recent tries."
            : "\(num(pct(vs!)))% \(vs! > 0 ? "faster" : "slower") than your recent tries."
    }
    private static func share(_ x: Double) -> String { x < 0.005 ? "less than 1" : num(pct(x)) }
    static func tracingAccuracy(_ acc: Double, _ limit: Double) -> String {
        "On average your line was \(share(acc))% of the spiral's size away from the guide. A hit needs \(num(pct(limit)))% or less."
    }
    static func tracedShare(_ cover: Double, _ what: String) -> String { "You traced \(num(pct(cover)))% of the \(what)." }
    static func keptUp(_ lag: Double, _ lead: Double, _ limit: Double) -> String {
        lag < 0.15 ? "You kept up with the dot."
            : "On average you were \(toFixed(lag, 1)) beats from the dot, mostly \(lead < 0 ? "behind" : "ahead of") it. " +
              "A hit needs \(num(limit)) or less."
    }
    static func waveNear(_ near: Double, _ limit: Double) -> String {
        "On average your line was \(share(near))% of the wave's height away from it. A hit needs \(num(pct(limit)))% or less."
    }
    static func caughtSentence(_ caught: Double, _ of: Double, _ need: Double) -> String {
        "You caught \(num(caught)) of \(num(of)) circles. A hit needs \(num(need))."
    }
    static func reactionSentence(_ ms: Double) -> String {
        ms.isFinite ? "You typically tapped a circle \(toFixed(ms / 1000, 2)) seconds after it appeared." : "No circles caught yet."
    }
    static func extraTapsSentence(_ n: Double, _ allowed: Double) -> String {
        (n == 0 ? "Every tap landed on a circle." : "\(num(n)) tap\(n == 1 ? "" : "s") missed every circle.") +
            (allowed > 0 ? " A hit allows \(num(allowed)) or fewer." : " A hit allows none.")
    }
    static let levelUp: [String: (Int) -> String] = [
        "big-writing": { n in "Level up. Level \(n) has a taller target line." },
        "steady-tracing": { n in "Level up. Level \(n)'s guide is fainter." },
        "rhythm": { n in "Level up. Level \(n) has a faster beat." },
        "hand-skills": { n in "Level up. Level \(n)'s circles start smaller." },
    ]
    private static func downTo(_ n: Int) -> String { "Three misses in a row, so you're back to Level \(n)." }
    static let levelDown: [String: (Int) -> String] = [
        "big-writing": { n in "\(downTo(n)) The target line is a little lower." },
        "steady-tracing": { n in "\(downTo(n)) The guide is a little clearer." },
        "rhythm": { n in "\(downTo(n)) The beat is a little slower." },
        "hand-skills": { n in "\(downTo(n)) The circles start a little bigger." },
    ]
    static func tooHardToast(_ n: Int) -> String { "Moved down to Level \(n)" }
    static let tooHardLowest = "You're already on Level 1, the easiest level."
    static let notBuilt = "Not built yet"

    static let progressBlurb = "Your first check-in next to your latest, measure by measure."
    static let progressEmpty = "Do two check-ins with the same hand and the same pen or finger to compare them here."
    static let progressCaption =
        "Both check-ins are placed against the same reference group, so the comparison is fair. Single check-ins vary " +
        "from day to day, so a change between two of them is one reading, not a trend."
    private static let inputPhrase = ["pencil": "an Apple Pencil", "touch": "a finger", "mouse": "a mouse"]
    static func drawnIn(_ seconds: Double) -> String { "Drawn in \(toFixed(seconds, 1)) seconds" }
    static let replayMissing = "No drawing was kept for this check-in."
    static func progressSetup(_ hand: String, _ inputType: String?) -> String {
        "Comparing check-ins drawn with your \(hand) hand, using \(inputType.flatMap { inputPhrase[$0] } ?? "the same input")."
    }
    static func timingSetup(_ hand: String, _ inputType: String?) -> String {
        "Counts check-ins drawn with your \(hand) hand and \(inputType.flatMap { inputPhrase[$0] } ?? "the same input")."
    }
    static let handsEmpty =
        "Do one check-in with each hand, with the same pen or finger, within a week of each other. They'll show up here side by side."
    static func handsSetup(_ inputType: String?) -> String {
        "Your newest left hand and right hand check-ins, both drawn with \(inputType.flatMap { inputPhrase[$0] } ?? "the same input"), " +
        "within a week of each other."
    }
    static let handsCaption =
        "Most people draw a little differently with each hand, especially the one they don't write with. A gap here isn't a " +
        "warning sign on its own. A gap that grows over time is worth mentioning to a doctor."

    static let accentHelp = "Changes the color of buttons, links and highlights."
    static let motionHelp = "Reduced turns off moving effects. Automatic follows your device's setting."
    static let saved = "Saved"
    static func spiralSaved(_ n: Int) -> String { "Spiral \(n) saved" }
    static let measuring = "Measuring your spiral"
    static let measureSteps = [
        "Cleaning up the line",
        "Smoothing out screen jitter",
        "Measuring 12 things about it",
        "Comparing with the reference group",
    ]
    static let accents = ["Blue", "Indigo", "Violet", "Teal", "Amber", "Rose", "Graphite"]

    static let collectConsent = "Written consent for this participant is on file."
    static let diagnosisNote =
        "Only participants with no diagnosis are added to the healthy reference. Everyone else is kept, labeled and left out of it."
    static let medHelp = "A rough answer is fine. Leave it empty if unsure."
    static let noParticipants = "No participants on this iPad yet."
    static let unexportedHelp = "Sessions are only stored on this iPad. Export them before deleting the app."
    static let exported = "Exported"
    static let leaveSession = "Leave this session?"
    static let leaveSessionDetail = "The spirals drawn so far will be discarded."
    static let diagnoses = ["none": "None", "parkinsons": "Parkinson\u{2019}s", "essential_tremor": "Essential tremor", "other": "Other"]
    static func bracketNote(_ age: Int) -> String {
        age < 60 ? "Counts toward the under-60 reference group." :
        age >= 80 ? "Counts toward the 80+ reference group." :
        "Counts toward the \(Int(floor(Double(age) / 10)) * 10)s reference group."
    }
}
