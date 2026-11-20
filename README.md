<h1 align="center">Atlas · exelight7 edition</h1>

<p align="center">
  <a href="https://github.com/exelight7/Atlas/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/exelight7/Atlas?style=for-the-badge&color=1A91FF"/></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/exelight7/Atlas?style=for-the-badge&color=1A91FF"/></a>
  <a href="https://github.com/Atlas-OS/Atlas"><img alt="Upstream" src="https://img.shields.io/badge/upstream-Atlas--OS%2FAtlas-1A91FF?style=for-the-badge&logo=github"/></a>
</p>

<p align="center">
  A community fork of <a href="https://github.com/Atlas-OS/Atlas">AtlasOS</a> focused on <b>gaming performance</b> and a <b>lighter Windows</b>,<br>
  without touching anything anti-cheat depends on.
</p>

<p align="center">
  <a href="https://github.com/exelight7/Atlas/releases/latest">⬇️ Download</a>
  •
  <a href="#-whats-different-in-this-fork">✨ What's different</a>
  •
  <a href="#-installing">🚀 Install</a>
  •
  <a href="https://docs.atlasos.net">📚 Atlas docs</a>
</p>

> [!NOTE]
> This is **not** the official AtlasOS. It is an independent fork that tracks upstream Atlas 0.6 and adds opt-in changes on top.
> For the official project, go to [Atlas-OS/Atlas](https://github.com/Atlas-OS/Atlas) and [atlasos.net](https://atlasos.net).
> Please report problems with this fork [here](https://github.com/exelight7/Atlas/issues), not to the Atlas team.

## 🤔 What is Atlas?

Atlas is an open-source Windows configuration project. It applies privacy, usability and performance settings, and installs **AtlasDesktop** controls so you can change or revert individual choices after installation.

This fork keeps everything upstream Atlas 0.6 does and adds the changes below.

## ✨ What's different in this fork

Every change follows the same rules:

- **Revertible:** each change is a toggle with an `AtlasDesktop` launcher to enable it and another to restore the Windows default.
- **Tested:** each one ships with Pester tests and passes the same lint and build checks as upstream.
- **Measured:** nothing is added without a before/after measurement.
- **Anti-cheat safe:** Secure Boot, TPM, test-signing, driver signature enforcement and anti-cheat services (Vanguard, EasyAntiCheat, BattlEye) are never modified.

### 🎮 Gaming

| Toggle | What it does | Docs |
|---|---|---|
| **Windowed Game Optimizations** | Turns on Windows' flip-model upgrade for DirectX 10/11 games in windowed or borderless mode, for lower latency and Auto HDR / VRR support. | [gaming-toggles.md](docs/gaming-toggles.md) |
| **Processor Performance Preference** | Sets the CPU's energy-performance preference (EPP) to maximum performance on AC power, and keeps it when you switch power plans. | [gaming-toggles.md](docs/gaming-toggles.md) · [power-saving-policy.md](docs/power-saving-policy.md) |
| **FSO / Game Bar: Disable Capture** | A new third state that keeps Game Bar but turns off background recording (Game DVR). | [gaming-toggles.md](docs/gaming-toggles.md) |

### 🪶 Lighter system

| Toggle | What it does | Docs |
|---|---|---|
| **Lite Tasks** | Disables 29 telemetry and maintenance scheduled tasks that upstream Atlas leaves on. Every task can be restored. | [lite-tasks.md](docs/lite-tasks.md) |

### 📊 Tooling

- `tools/dev/Measure-AtlasPerformance.ps1` captures a JSON snapshot covering:
  - idle CPU, memory, processes and services
  - GPU scheduling state
  - processor power settings
  - CPU performance and frequency
  - scheduled tasks that ran in the last 24 hours

  Run it before and after a change to compare the two.

## 🚀 Installing

> [!IMPORTANT]
> Create a **System Restore Point** before installing or upgrading.

**Requirements**
- Windows 11 **25H2** (build 26200) or **26H2** (build 26300), freshly installed.
- Or an existing Atlas 0.4.1 / 0.5.0 / 0.6.0 install on a supported build. See the [upgrade requirements](docs/upgrading.md).

**Steps**
1. Download `AtlasPlaybook_v0.6.1.apbx` from the [latest release](https://github.com/exelight7/Atlas/releases/latest).
2. Check its SHA256 against `SHA256SUMS.txt` from the same release:
   ```powershell
   Get-FileHash .\AtlasPlaybook_v0.6.1.apbx -Algorithm SHA256
   ```
3. Open the package with [AME Wizard](https://amelabs.net) and follow the steps.
4. Open the `AtlasDesktop` folder on your desktop or Start menu. The new toggles are there next to the upstream ones.

After installing, `AtlasDesktop\9. Troubleshooting\Check Atlas Health.cmd` reports what Atlas installed and which settings have changed since. It changes nothing.

### Atlas Toolbox

The released Atlas Toolbox (0.1.x) only supports Atlas 0.5 and refuses to start on 0.6. Two ways around it:

- Use the `AtlasDesktop` folder until Toolbox 0.2 is released.
- Build Toolbox from the [atlas-toolbox](https://github.com/Atlas-OS/atlas-toolbox) `main` branch, which already supports Atlas 0.6.

## 🔍 Open source and transparent

The Atlas package is a renamed **.zip** archive with the password `malte`, so you can inspect every file before it runs. Most of it is PowerShell and data definitions that run on the Windows PowerShell 5.1 built into Windows.

- **[Architecture](docs/architecture.md):** how an install runs.
- **[Toggle catalog](docs/catalog/toggles.md):** every toggle and install tweak, generated from the source.
- **[Binary inventory](playbook/Executables/AtlasModules/README.md):** every bundled executable, with its hash, source and license.

Atlas does not change Windows activation and does not distribute Windows. You need your own Windows installation and license.

## 🛠️ Developing

| Guide | Covers |
|---|---|
| [Contributing](.github/CONTRIBUTING.md) | Quick start for building and testing |
| [Building](docs/building.md) | Producing the `.apbx` package |
| [Testing](docs/testing.md) | Pester suites and CI checks |
| [Publication checklist](docs/publication.md) | Release evidence |

A new optimization in this fork needs all of the following:
- a toggle (`Toggles/<Group>/<Name>.psd1` + `.ps1`)
- Pester tests
- regenerated launchers and catalog
- a clean lint
- a before/after measurement
- its own commit

## 📜 License and credits

Licensed under [GPLv3](LICENSE), like upstream.

All credit for Atlas itself goes to the [Atlas-OS team and contributors](https://github.com/Atlas-OS/Atlas/graphs/contributors). This fork only adds the changes listed above. The AtlasOS name and logo belong to the Atlas project.
