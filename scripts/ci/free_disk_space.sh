#!/usr/bin/env bash
# Frees up disk space on the CI runner before the Android build.
#
# Extracted from build-android.yml (was the "Free disk space" step) —
# behavior unchanged, only its location.
set -euo pipefail

echo "Disk before cleanup:"
df -h
sudo rm -rf /usr/share/dotnet
sudo rm -rf /usr/local/lib/android/sdk/ndk
sudo rm -rf /opt/ghc
sudo rm -rf /usr/local/share/boost
sudo apt-get clean
echo "Disk after cleanup:"
df -h
