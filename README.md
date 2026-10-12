# RigPilot Shell (iPhone)

**[⬇ Download the latest RigPilot.ipa](https://github.com/RashestLynx/connectbot.ios/releases/latest/download/RigPilot.ipa)** · [All releases](https://github.com/RashestLynx/connectbot.ios/releases)

Control your computer from your phone over SSH: a host list, password or key
login, and a terminal with Esc/Ctrl/Tab/arrow keys above the keyboard.
Inspired by [ConnectBot](https://connectbot.org) for Android (not affiliated).

It is new Swift code (Android code can't run on iOS), built on
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (terminal, MIT) and
[Citadel](https://github.com/orlandos-nl/Citadel) (SSH, MIT).

## Build

GitHub Actions builds an unsigned `RigPilot.ipa` on every push to `main`
(Actions tab → **iPhone Build** → the run → **Artifacts**). No Mac needed.

## Install (free Apple ID)

1. Install [Sideloadly](https://sideloadly.io) and iTunes (from apple.com, not the
   Microsoft Store) on the Windows PC.
2. Plug the iPhone in with a cable, trust the computer.
3. Drag `RigPilot.ipa` into Sideloadly, enter your Apple ID, click **Start**.
4. On the iPhone: Settings → General → VPN & Device Management → trust your
   Apple ID. On iOS 16+ also turn on Settings → Privacy & Security →
   **Developer Mode** (the phone restarts).

With a free Apple ID the app stops opening after 7 days: run Sideloadly again
to renew it (your hosts and keys are kept).

## Use

Tap **+**, fill in Username, Host and Port, Save, tap the host. The first
connection to a computer saves its host key; a different key later is refused.
**⋯ → Keys** creates an Ed25519 key for password-free login.
