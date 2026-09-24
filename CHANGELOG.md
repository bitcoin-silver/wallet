# Changelog

All notable changes to the Bitcoin Silver Android wallet are documented in this file. Versions before 6.4 are summarised in the README under "Latest Updates" and in the git tags.

## [Unreleased]

- No unreleased changes yet.

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
