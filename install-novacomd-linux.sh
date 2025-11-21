#!/usr/bin/env bash
# This is free and unencumbered software released into the public domain.
# Author: NotAlexNoyle (alexnoyle@icloud.com)

# Build novacomd and capture the output.
output="$(make host 2>&1)"

# Keep track of the build status.
status=$?

# DEBUG: Show the output in the console.
printf '%s\n' "$output"

# Check if the build succeeded.
if [ $status -eq 0 ]; then
    # Build succeeded -> return 1.
    exit 1
fi

# Build failed. If the reason is missing usb.h, return 0.
if printf '%s\n' "$output" | grep -q 'usb.h: No such file or directory'; then
    echo 0
fi

#Return with other failure condition.
exit "$status"
