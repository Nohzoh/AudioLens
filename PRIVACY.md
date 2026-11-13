# Privacy Policy — AudioLens

**Last updated: November 13, 2026**

AudioLens ("the app") is developed and published by an individual
developer. This policy explains what data the app accesses, why, and
what happens to it. AudioLens is available on Android; no account or
sign-up is required to use it.

## Summary

- AudioLens does **not** collect analytics, does **not** track you, and
  does **not** sell or share your data with advertisers.
- Photos and location are used only to generate your audio guide.
- Your **photo** leaves your phone only in cloud (Gemini API) mode, or if
  you attach it to a report you choose to send.
- To find out what is around you, the app looks up the photo's
  **location** on OpenStreetMap, Wikipedia and Wikidata **in both modes**
  (on-device and cloud), when location is available and the phone is
  online — see below.
- In on-device mode (Gemini Nano) and offline, nothing leaves your phone.
- All data the app stores (history, API key) stays on your device.

## Data the app accesses, and why

| Data | Why | Leaves your device? |
|---|---|---|
| **Camera** | To take a photo of the place you want a guide for | Only in cloud mode, or in a report you send (see below) |
| **Photos (gallery)** | If you choose an existing photo instead of the camera | Same as above |
| **Location (GPS)** | To identify where the photo was taken, so the guide can name the actual place (the photo's EXIF GPS data first, then the device's live location if needed) | Coordinates go to OpenStreetMap, Wikipedia and Wikidata in both modes, and the resulting place context to Google in cloud mode (see below) |

### Cloud mode (Gemini API)

When you configure a Gemini API key (Settings) and use the cloud
analysis mode, the photo and, if available, location-derived context
(address, nearby point-of-interest name) are sent to **Google's Gemini
API** (`generativelanguage.googleapis.com`) to generate the audio
guide's script and voice. This is a direct API call from your device to
Google — AudioLens's developer does not have a server that sees this
data. Google's own privacy policy and terms govern how the Gemini API
processes this data: <https://policies.google.com/privacy>.

In cloud mode, the guide's text is also sent to Google to be read
aloud (Gemini voice), and the follow-up questions you ask about a guide
are sent to Google with the guide's text and place context.

### Location lookups (both modes)

To enrich the description with real facts about the location, in
**on-device and cloud mode alike**, whenever the photo has a location and
the phone is online, the app queries:
- **OpenStreetMap** (Nominatim reverse-geocoding and the Overpass API)
  — sends coordinates to identify the address, nearby points of interest
  and tall landmarks visible from there.
- **Wikipedia** — sends coordinates or the identified place name to find
  relevant background information.
- **Wikidata** — sends the identifier of the identified place to get a
  short description of it.

These requests contain no name, account or identifier beyond the
coordinates or place needed for that request; they identify the app
itself (name, version and project address) as these services require.
Turning off location access (or using a photo without location) means
none of these lookups happen.

### On-device mode (Gemini Nano)

When you use the on-device analysis mode (Gemini Nano, where supported
by your device), the photo is analyzed and the guide is read aloud
entirely on your phone using Android's on-device AI. **The photo never
leaves your device** in this mode; only the location lookups described
above use the network.

### Reports you send (feedback)

If you choose to send a report from the app (« Envoyer un retour »), its
text — and, only if you add them, a screenshot or a photo and the
details of one of your analyses (its text, the place named, the
Wikipedia articles used) — is sent to the developer through a
**Telegram** bot (`api.telegram.org`). Nothing is sent unless you press
send. Telegram's privacy policy applies to that transfer:
<https://telegram.org/privacy>.

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
