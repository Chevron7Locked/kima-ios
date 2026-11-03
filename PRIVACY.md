# Privacy policy

**Kima for iOS** — the native client for your self-hosted Kima server.
Effective 2026-11-02.

## 1. Summary

Kima talks to your own server, plus the few services listed in section 4. Nothing that identifies you is sent to the developer: no
backend, no analytics, no tracking, no ads. Delete the app and nothing of yours is left with us.

## 2. Stored on this device

- Your server address and sign-in token, kept in the iOS keychain on this device only. They are
  never synced and are sent only to your server.
- App preferences (playback speed, sort order, display settings), stored on this device.
- Plays recorded while offline, kept until they're sent to your server (track ids and times
  only, never passwords).
- Cover art is cached in memory only. Nothing that needs your sign-in is saved to disk.
- Problem reports you file (your note, the screen, what was playing, the app and iOS versions, the
  device model, and your server address), kept until you clear them in settings › issue reports.
- On devices that support Apple Intelligence, Home's daily line is reworded by Apple's on-device
  model from a bundled list of lines and the mood of what you play. This runs entirely on the
  device; nothing is sent anywhere.

## 3. What your server stores

Your play history, stats, playlists, and library info are stored on your server, on hardware you
choose. The app reads and changes that data but doesn't copy it anywhere else.

To delete your account, go to settings › delete account. This asks your server to delete your
account and the data it holds for you (play history, playlists, settings). Your server keeps the
music files themselves. A server's only administrator account can't be deleted this way.

The server has its own privacy policy:
[kima-hub PRIVACY.md](https://github.com/Chevron7Locked/kima-hub/blob/main/PRIVACY.md).

## 4. What the app connects to

- Your server: every request. The app checks the address of every request and attaches your
  sign-in only when it's your server, so it never goes to image sites.
- Cover art sites (iTunes, Deezer, and similar): images only, fetched directly and anonymously,
  with no cookies and no sign-in.
- Apple: keychain, background audio, lock screen controls. Apple's terms apply.
- GitHub: only when you tap "open on github" on a problem report. It opens GitHub's new-issue page
  with your note, the app and iOS versions, the device model, and the screen. Nothing is filed
  until you submit it there, from your own GitHub account.

No analytics, crash reporting, ad tracking, or telemetry of any kind. Every request the app
makes is in its network source files.

## 5. Changes

If this policy changes, the app's about screen and the changelog will say so, with the date.

## 6. Source code

The app's source code is public, so you can check all of this yourself:
[github.com/Chevron7Locked/kima-ios](https://github.com/Chevron7Locked/kima-ios).

## Contact

feedback@chevron7.io
