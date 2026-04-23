#!/usr/bin/env bash
set -euo pipefail


APP_DIR="${APP_DIR:-/opt/smartgo-fe}"
BRANCH="${BRANCH:-main}"
IMAGE_NAME="${IMAGE_NAME:-smartgo-fe}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY_HOST="${REGISTRY_HOST:-ghcr.io}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
REGISTRY_TOKEN="${REGISTRY_TOKEN:-}"

echo "==> Deploy SmartGo FE"
echo "App dir: ${APP_DIR}"
echo "Branch: ${BRANCH}"
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"

if [ ! -d "${APP_DIR}/.git" ]; then
  echo "Repository not found at ${APP_DIR}"
  echo "Clone your repository to this directory first."
  exit 1
fi

cd "${APP_DIR}"

if [ -n "${REGISTRY_USERNAME}" ] && [ -n "${REGISTRY_TOKEN}" ]; then
  echo "==> Login to ${REGISTRY_HOST}"
  echo "${REGISTRY_TOKEN}" | docker login "${REGISTRY_HOST}" --username "${REGISTRY_USERNAME}" --password-stdin
fi

echo "==> Fetch latest source"
git fetch --all --prune
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

echo "==> Pull and restart containers"
IMAGE_NAME="${IMAGE_NAME}" IMAGE_TAG="${IMAGE_TAG}" docker compose pull smartgo-fe
IMAGE_NAME="${IMAGE_NAME}" IMAGE_TAG="${IMAGE_TAG}" docker compose up -d --remove-orphans

echo "==> Cleanup dangling images"
docker image prune -f

echo "==> Deploy completed"