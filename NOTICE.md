# Third-Party Notices

DroidDock is an orchestration layer. It does **not** vendor any third-party
source code in this repository; instead, `scripts/fetch-binaries.sh` downloads
the official, pre-compiled macOS binaries at setup/build time and embeds them
into the application bundle. Each component remains under its own license.

| Component | Purpose | Upstream | License |
|-----------|---------|----------|---------|
| **scrcpy** (+ `scrcpy-server`; `SDL2`/`ffmpeg`/`libusb` statically linked) | Low-latency screen mirroring & input | <https://github.com/Genymobile/scrcpy> | Apache-2.0 |
| **Android Platform-Tools** (`adb`) | Device discovery, shell, input, install, push | <https://developer.android.com/tools/releases/platform-tools> | Android Software Development Kit License Agreement |

By running the setup script and distributing a built `DroidDock.app`, you are
redistributing the above components and must comply with their respective
license terms. The scrcpy `NOTICE`/`LICENSE` files and the Android SDK license
are included inside their downloaded archives.

The DroidDock application code itself (everything under `DroidDock/`, `scripts/`,
`project.yml`, and `Makefile`) is licensed under the MIT License — see `LICENSE`.
