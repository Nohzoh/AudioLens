# Privacy Policy — AudioLens

**Last updated: August 18, 2026**

AudioLens ("the app") is developed and published by an individual
developer. This policy explains what data the app accesses, why, and
what happens to it. AudioLens is available on Android; no account or
sign-up is required to use it.

## Summary

- AudioLens does **not** collect analytics, does **not** track you, and
  does **not** sell or share your data with advertisers.
- Photos and location are used only to generate your audio guide, and
  are sent to third-party services **only when you use the cloud (Gemini
  API) mode** — see below.
- You can use AudioLens entirely offline/on-device (Gemini Nano mode),
  in which case no photo or location data ever leaves your phone.
- All data the app stores (history, API key) stays on your device.

## Data the app accesses, and why

| Data | Why | Leaves your device? |
|---|---|---|
| **Camera** | To take a photo of the place you want a guide for | No — only if you use cloud mode (see below) |
| **Photos (gallery)** | If you choose an existing photo instead of the camera | Same as above |
| **Location (GPS)** | To identify where the photo was taken, so the guide can name the actual place (falls back to the photo's EXIF GPS data first, then the device's live location if needed) | Same as above |

### Cloud mode (Gemini API)

When you configure a Gemini API key (Settings) and use the cloud
analysis mode, the photo and, if available, location-derived context
(address, nearby point-of-interest name) are sent to **Google's Gemini
API** (`generativelanguage.googleapis.com`) to generate the audio
guide's script and voice. This is a direct API call from your device to
Google — AudioLens's developer does not have a server that sees this
data. Google's own privacy policy and terms govern how the Gemini API
processes this data: <https://policies.google.com/privacy>.

To enrich the description with real facts about the location, the app
may also query:
- **OpenStreetMap** (Nominatim reverse-geocoding and the Overpass API)
  — sends coordinates to identify the address and nearby points of
  interest.
- **Wikipedia** — sends the identified place name or coordinates to
  find relevant background information.

None of these third-party requests include your name, account, or any
identifier beyond the coordinates/photo needed for that specific
request.

### On-device mode (Gemini Nano)

When you use the on-device analysis mode (Gemini Nano, where supported
by your device), the photo is processed entirely on your phone using
Android's on-device AI. **No photo or location data leaves your device**
in this mode.

## Data stored on your device

- **Analysis history** (photos, scripts, generated audio, and their
  associated location) is stored locally in the app's private storage
  (SQLite database), for you to revisit past guides. It is not backed
  up to any cloud service AudioLens controls, and the app disables
  Android's automatic cloud backup for its data.
- **Your Gemini API key**, if you provide one, is stored using Android's
  encrypted secure storage (Keystore-backed), not in plain text.
- Deleting a history entry in the app permanently deletes its photo and
  audio file from your device.
- Uninstalling the app removes all of this data.

## Permissions

| Permission | Purpose |
|---|---|
| Camera | Take a photo to analyze |
| Location (fine/coarse) | Identify where a photo was taken |
| Notifications | Tell you when a background analysis has finished or failed |
| Foreground service | Keep an analysis running reliably if you switch away from the app while it's in progress |

You can deny camera/location access and still use the app with an
existing photo that has no location — the guide will simply be less
precise.

## Children's privacy

AudioLens is not directed at children and does not knowingly collect
data from children.

## Changes to this policy

If this policy changes, the update will be reflected here with a new
"Last updated" date.

## Contact

Questions about this policy or your data can be sent to:
**thomas.arnaud@gmail.com**
