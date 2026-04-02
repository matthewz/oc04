#!/bin/bash
set -euo pipefail

      TRIES=0
      MAX_TRIES=60

      until kubectl get nodes --request-timeout=5s 1> /dev/null 2>&1
      do
        TRIES=$((TRIES+1))
        if [ "$TRIES" -ge "$MAX_TRIES" ]
        then
          echo "❌ Cluster never became ready after $((MAX_TRIES*10))s — aborting"
          exit 1
        fi
        echo "   ...waiting for cluster API (attempt $TRIES/$MAX_TRIES)"
        sleep 10
      done

      echo "✅ Cluster API is responding"

exit 0
