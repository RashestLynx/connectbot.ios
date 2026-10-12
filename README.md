# ConnectBot for iPhone

A small SSH client for iPhone modelled on my Android build of
[ConnectBot](https://github.com/RashestLynx/connectbot): a host list, password or
key login, and a terminal with Esc/Ctrl/Tab/arrow keys above the keyboard.

It is new Swift code (Android code can't run on iOS), built on
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (terminal, MIT) and
[Citadel](https://github.com/orlandos-nl/Citadel) (SSH, MIT). The app icon comes
from ConnectBot (Apache-2.0).

## Build

GitHub Actions builds an unsigned `ConnectBot.ipa` on every push to `main`
(Actions tab → **iPhone Build** → the run → **Artifacts**). No Mac needed.

## Install (free Apple ID)

1. Install [Sideloadly](https://sideloadly.io) and iTunes (from apple.com, not the
   Microsoft Store) on the Windows PC.
2. Plug the iPhone in with a cable, trust the computer.
3. Drag `ConnectBot.ipa` into Sideloadly, enter your Apple ID, click **Start**.
4. On the iPhone: Settings → General → VPN & Device Management → trust your
   Apple ID. On iOS 16+ also turn on Settings → Privacy & Security →
   **Developer Mode** (the phone restarts).

With a free Apple ID the app stops opening after 7 days: run Sideloadly again
to renew it (your hosts and keys are kept).

## Use

Tap **+**, fill in Username, Host and Port, Save, tap the host. The first
connection to a computer saves its host key; a different key later is refused.
**Keys** creates an Ed25519 key for password-free login.
