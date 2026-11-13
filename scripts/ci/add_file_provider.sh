#!/usr/bin/env bash
# Adds the FileProvider entry + its file_paths.xml resource.
#
# #537: limited to cache/share/ — the app's own code shares nothing
# through this provider (share_plus and image_picker declare their own),
# so it must not expose external storage or the whole cache.
#
# Extracted from build-android.yml (was the "Add FileProvider" step) —
# behavior unchanged, only its location.
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
if ! grep -q 'FileProvider' "$MANIFEST"; then
  sed -i 's|</application>|    <provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.fileprovider" android:exported="false" android:grantUriPermissions="true"><meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/file_paths"/></provider>\n    </application>|' "$MANIFEST"
fi
mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/file_paths.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="shared" path="share/"/>
</paths>
XML
echo "FileProvider configured"
