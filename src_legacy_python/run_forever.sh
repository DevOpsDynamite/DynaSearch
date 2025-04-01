#!/bin/bash

PYTHON_SCRIPT_PATH=$1

# Uncomment the line below if you plan to use TMP, otherwise remove it.
# TMP="This variable might become useful at some point. Otherwise delete it." 

while true; do
    # Directly check the exit status of the command:
    if ! python3 "$PYTHON_SCRIPT_PATH"; then
        exit_code=$?
        echo "Script crashed with exit code ${exit_code}. Restarting..." >&2
        sleep 1
    fi
done
