#!/bin/bash

# Repository details
OWNER="Fidelisesq"
REPO="AWS-Cloud-Resume"

# List the first 470 workflow run IDs and store them in an array
RUN_IDS=$(gh run list --repo "$OWNER/$REPO" --limit 470 --json databaseId -q '.[].databaseId')

# Loop through each run ID and delete it
for RUN_ID in $RUN_IDS; do
  echo "Deleting workflow run ID: $RUN_ID"
  gh run delete "$RUN_ID" --repo "$OWNER/$REPO"
done
