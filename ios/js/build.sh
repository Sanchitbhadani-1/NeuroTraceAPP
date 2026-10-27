#!/bin/bash
# BUILD.SH REBUILDS NEUROTRACE/RESOURCES/NT-CORE.JS FROM THE TEAM'S JAVASCRIPT IN APP/CORE/
# RUN IT WITH bash js/build.sh AFTER ANY CHANGE TO THE FILES IN app/core/, IT NEEDS NODE

# Go to the ios folder and bundle js/core.js into one file with esbuild
cd "$(dirname "$0")/.." && npx --yes esbuild@0.25.10 js/core.js --bundle --format=iife --global-name=NT --target=safari17 --outfile=NeuroTrace/Resources/nt-core.js
