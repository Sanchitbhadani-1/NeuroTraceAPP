import Foundation

enum Copy {

    static let notADiagnosis =
        "These are measurements of how you moved during the tasks, compared with other people who " +
        "took the same tasks. They are not a diagnosis and cannot tell you whether you have a " +
        "neurological condition."

    static let pitch = "NeuroTrace turns an ordinary iPad into a motor-function measurement tool."
    static let tracks = "It reports where each measure falls relative to a reference population and tracks how it changes over time."
    static let onDevice = "All analysis runs on this device. Your data only leaves it if you choose to share it."

    static let howSteps = [
        "Trace a spiral on the screen with your finger or an Apple Pencil.",
        "NeuroTrace measures 12 things about the line: its shape, speed, smoothness and tremor.",
        "A machine-learning model, trained on spiral drawings from 112 people with and without Parkinson's, combines all 12 into one result.",
        "Each measure is placed among a reference group of healthy adults.",
    ]
    static let credit = "Made by Sanchit Bhadani, Aryan Modi, and Mihir Malladi for the 2026 Congressional App Challenge."

    static let loginNote = "Accounts aren't set up yet. For now, logging in opens the app on this device."
    static let measuring = "Measuring your spiral"
    static let measureSteps = [
        "Cleaning up the line",
        "Smoothing out screen jitter",
        "Measuring 12 things about it",
        "Comparing with the reference group",
    ]
}
