#!/bin/sh

# validate subscription status
API_URL="https://agent.api.stepsecurity.io/v1/github/$GITHUB_REPOSITORY/actions/subscription"

# Set a timeout for the curl command (3 seconds)
RESPONSE=$(curl --max-time 3 -s -w "%{http_code}" "$API_URL" -o /dev/null) || true
CURL_EXIT_CODE=${?}

# Check if the response code is not 200
if [ "$CURL_EXIT_CODE" -ne 0 ] || [ "$RESPONSE" != "200" ]; then
  if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "000" ] || [ "$CURL_EXIT_CODE" -ne 0 ]; then
    echo "Timeout or API not reachable. Continuing to next step."
  else
    echo "Subscription is not valid. Reach out to support@stepsecurity.io"
    exit 1
  fi
fi

set -eu

VERSION="${REVIEWDOG_VERSION:-latest}"

TEMP="${REVIEWDOG_TEMPDIR}"
if [ -z "${TEMP}" ]; then
  if [ -n "${RUNNER_TEMP}" ]; then
    TEMP="${RUNNER_TEMP}"
  else
    TEMP="$(mktemp -d)"
  fi
fi

INSTALL_SCRIPT='https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh'
if [ "${VERSION}" = 'nightly' ]; then
  INSTALL_SCRIPT='https://raw.githubusercontent.com/reviewdog/nightly/master/install.sh'
  VERSION='latest'
fi

mkdir -p "${TEMP}/reviewdog/bin"

echo '::group::🐶 Installing reviewdog ... https://github.com/reviewdog/reviewdog'
(
  if command -v curl 2>&1 >/dev/null; then
    curl -sfL "${INSTALL_SCRIPT}"
  elif command -v wget 2>&1 >/dev/null; then
    wget -O - "${INSTALL_SCRIPT}"
  else
    echo "curl or wget is required" >&2
    exit 1
  fi
) | sh -s -- -b "${TEMP}/reviewdog/bin" "${VERSION}" 2>&1
echo '::endgroup::'

echo "${TEMP}/reviewdog/bin" >>"${GITHUB_PATH}"
