# Changelog

All notable changes to the Bitcoin Silver Android wallet are documented in this file. Versions before 6.4 are summarised in the README under "Latest Updates" and in the git tags.

## [Unreleased]

### Security

- The NonKYC API key is no longer built into the app. The exchange screen only reads public market data (`/market/info`), which needs no key; the old key was revoked on the NonKYC account. `NONKYC_API_KEY` is gone from `dart_defines.json` and the iOS workflow.

### Documentation

- README: new "iOS Release (GitHub Actions)" section on starting the manual iOS workflow, the version and build number it needs, the repository secrets it uses, and what to check when it fails.

### Changed

- iOS release workflow: Flutter pinned to 3.47.5 (was: whatever stable release was newest on the day of the run), matching local and Android builds.

## [6.4.1] - Play Store versionCode 89, iOS build 6.4.1+5

Matches web wallet 3.1.1 (same payment request safety rules).

### Security

- Payment requests: the name in a request is shown as "Name given in the request (not verified)". "Saved contact: …" appears only when the address matches a saved contact.
- A request that uses the name of a saved contact for a different address shows a red warning.
- Control, zero-width and direction-override characters (such as U+202E) are removed from a request's name and note; long notes are shortened by character, so emoji are never cut in half.
- Scanning a QR code into the address book no longer suggests a name that another contact already has.
- The request card reminds you to pay only requests from people you trust.

### Fixed

- Startup: the start screen waited for all network loading, one step after the other (RPC check up to 4 seconds, then explorer history and balance with no time limit), so it was sometimes short and sometimes long. It now waits only for the wallet to load from the device; history and balance load in parallel afterwards while the wallet screen shows its loading placeholders.
- Returning to the app showed "No Transactions Yet" for a moment: a background refresh emptied the list before asking the explorer, and left it empty if the request failed. The list now stays on screen and is replaced only when fresh data arrives.
- Fingerprint lock now covers every screen. Before, returning to the app locked only the home screen: a screen opened on top of it (Send, Receive, Settings, a dialog) stayed visible and usable without unlocking. The lock is now shown on top of everything, the back button cannot close it, and the screen you were on comes back unchanged after unlocking.
- With fingerprint lock on, resuming also rebuilt the whole home screen, so its refresh could be skipped and its state was reset. The home screen now stays in place under the lock and refreshes while you unlock.

### Added

- Address book: each contact has a Send button that opens Send with the address filled in, like the web wallet's Contacts tab.

## [6.4] - Play Store versionCode 88, iOS build 6.4.0+4

(versionCode 87 was an internal test upload of the same code, built without stripping debug info. The README's bundle command now passes `--extra-gen-snapshot-options=--strip`.)

Works together with web wallet 3.1: both use the same payment requests and `.btcs` address book files.

### Added

- Payment requests are read in full. Scanning a `bitcoinsilver:` QR code (or pasting one, or a web wallet payment link, into the recipient field) fills in the address and the amount. A card shows the requested amount, the recipient's name and the note, and warns when the amount is changed. Nothing is sent without the usual confirmation, and the note is never sent.
- Sharing a payment request from the Receive screen includes a link that opens it in the web wallet (`https://bitcoinsilver.top/web-wallet/#pay=...`) and the `bitcoinsilver:` request itself.
- Scanning a QR code into the address book also fills in the label when the code has one (for example a miner's `?label=miner-3`).

### Changed

- "Request Amount" needs a valid amount: above 0, at most 8 decimals, no exponent. The amount is stored in a standard form (for example `01.50` becomes `1.5`), and the note is limited to 200 characters.
- The scanner returns the full scanned text, and each screen reads it with the shared payment request code (`lib/services/payment_request.dart`, kept identical to the web wallet's). Codes it cannot read still fill in the address part as before, with a message saying why.

### Fixed

- Exporting the address book over an existing, longer `BTCS_contacts.btcs` left part of the old file at the end, so the export could not be imported by this app or the web wallet. Exports are now written with truncation and their size is checked.
- Files damaged this way by earlier versions can be imported again, as long as the export at the start of the file is complete (its contact count matches).
- The "incomplete file" import message showed the whole contact list instead of the number of contacts.
