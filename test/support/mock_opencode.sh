#!/bin/sh
if [ "$MOCK_OPENCODE_SCENARIO" = "timeout" ]; then
  sleep 30
  exit 0
fi

if [ "$MOCK_OPENCODE_SCENARIO" = "multi_chunk" ]; then
  echo "first line"
  sleep 0.1
  echo "second line"
  sleep 0.1
  echo "third line"
  exit 0
fi

if [ "$MOCK_OPENCODE_SCENARIO" = "failure" ]; then
  echo "error occurred" >&2
  exit 1
fi

echo "mock opencode session"
exit 0
