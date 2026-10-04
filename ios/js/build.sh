#!/bin/bash
# Rebuilds NeuroTrace/Resources/nt-core.js from the team's JavaScript in app/
# Run it after any change to nt-features.js, nt-filters.js, nt-signal.js, score.js, train.js, tapping.js,
# homescan.js, meds.js or hands.js, so the iPad app runs the new version. Needs Node
cd "$(dirname "$0")/.." && npx --yes esbuild@0.25.10 js/core.js --bundle --format=iife --global-name=NT --target=safari17 --outfile=NeuroTrace/Resources/nt-core.js
