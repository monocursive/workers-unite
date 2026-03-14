#!/bin/bash
set -e

# Wait for PostgreSQL to accept TCP connections
until bash -c "echo > /dev/tcp/${DB_HOST:-localhost}/5432" 2>/dev/null; do
  echo "Waiting for PostgreSQL at ${DB_HOST:-localhost}:5432..."
  sleep 2
done
echo "PostgreSQL is ready."

# Full setup only when deps volume is empty (first run)
if [ ! -d "deps/phoenix" ]; then
  echo "First run — running full setup..."
  mix setup
else
  echo "Deps present — running migrations only..."
  mix ecto.migrate
fi

# Start the Phoenix server
exec mix phx.server
