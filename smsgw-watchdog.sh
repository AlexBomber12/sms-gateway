#!/bin/bash
set -e
STATUS=$(docker inspect --format '{{.State.Health.Status}}' smsgateway || echo notfound)
if [ "$STATUS" = "unhealthy" ]; then
  logger -t smsgw "Container unhealthy – restarting"
  docker restart smsgateway
fi
