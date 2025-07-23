#!/bin/bash
set -e
STATUS=$(docker inspect --format '{{.State.Health.Status}}' smsgateway || echo "notfound")
if [ "$STATUS" = "unhealthy" ]; then
  docker restart smsgateway
fi
