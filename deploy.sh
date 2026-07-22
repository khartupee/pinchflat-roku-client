#!/usr/bin/env bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
ROKU_IP="192.168.1.15"          # <-- Replace with your Roku Ultra's local IP address
ROKU_PASSWORD="hubba"   # <-- Replace with your Developer Mode password
ROKU_USER="rokudev"             # Roku dev username is always 'rokudev'

# TARGET PATHS
# Resolve the directory of this script dynamically so it always packages the workspace folder
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${PROJECT_DIR}/build"
ZIP_FILE="${BUILD_DIR}/pinchflat-client.zip"

# Ensure our local build deployment folder exists
mkdir -p "${BUILD_DIR}"

# ==============================================================================
# EXECUTION STEPS
# ==============================================================================

echo "=== Step 1: Intercepting Roku Focus (ECP Port 8060) ==="
# Sending a 'Home' command forces the Roku OS to cleanly exit out of any 
# frozen or crashing instances of your app and returns to standard focus.
curl -sS -d '' "http://${ROKU_IP}:8060/keypress/Home"
sleep 1 # Give the system UI thread a brief moment to catch up

echo "=== Step 2: Packaging Channel Assets ==="
cd "${PROJECT_DIR}" || exit 1

# Erase the prior compressed build if it exists
rm -f "${ZIP_FILE}"

# CRUCIAL: Roku's compiler will crash if you zip the parent folder itself. 
# We must zip only the internal contents/folders relative to the root.
zip -r "${ZIP_FILE}" manifest source components images -x "*.git*" "build/*" > /dev/null

if [ -f "${ZIP_FILE}" ]; then
    echo "  Successfully built: $(basename "${ZIP_FILE}")"
else
    echo "  Error: Failed to construct the zip package bundle."
    exit 1
fi

echo "=== Step 3: Pushing Bundle to Developer Server (Port 80) ==="
# The device expects standard multipart form data via Digest authentication
RESPONSE=$(curl -sS --digest -u "${ROKU_USER}:${ROKU_PASSWORD}" \
               -F "mysubmit=Install" \
               -F "archive=@${ZIP_FILE}" \
               "http://${ROKU_IP}/plugin_install")

# ==============================================================================
# EVALUATING RESULTS
# ==============================================================================
if echo "$RESPONSE" | grep -q "Install Success"; then
    echo " Done! The channel has successfully compiled and initialized on your TV screen."
else
    echo " Deployment Failure. Check the Roku compiler feedback below:"
    # Extract clean text error highlights out of the device's returned raw HTML
    echo "$RESPONSE" | grep -oE '<font color="red">[^<]*</font>' | sed -e 's/<[^>]*>//g'
fi
