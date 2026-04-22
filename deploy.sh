#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/smartgo-fe}"
BRANCH="${BRANCH:-main}"

echo "==> Deploy SmartGo FE"
echo "App dir: ${APP_DIR}"
echo "Branch: ${BRANCH}"

if [ ! -d "${APP_DIR}/.git" ]; then
  echo "Repository not found at ${APP_DIR}"
  echo "Clone your repository to this directory first."
  exit 1
fi

cd "${APP_DIR}"

echo "==> Fetch latest source"
git fetch --all --prune
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

echo "==> Build and restart containers"
docker compose down
docker compose build --no-cache
docker compose up -d

echo "==> Cleanup dangling images"
docker image prune -f

echo "==> Deploy completed"
