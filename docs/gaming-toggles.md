# exelight7 gaming toggles

The `Toggles\Gaming` group holds the exelight7 gaming toggles. Each one is opt-in, can be
undone from its `(default)` launcher, and changes nothing Atlas applies at install. None of
them touch Secure Boot, TPM, test signing, driver signing or anti-cheat services
(Vanguard, Easy Anti-Cheat, BattlEye).

Launchers are in `AtlasDesktop\3. General Configuration\Gaming\`.

## How a gaming toggle is accepted

A toggle belongs here only when its effect can be measured on the machine before and
after the change. A tweak whose effect cannot be measured is left out, and the decision is
recorded. Nagle's algorithm (`TcpAckFrequency`/`TCPNoDelay`) is one example: it only
affects TCP, while the games it targets send gameplay traffic over UDP.

1. Measure the system with `tools\dev\Measure-AtlasPerformance.ps1`
   (see [testing.md](testing.md)).
2. Measure the game itself with the method the toggle lists below.
3. Apply the toggle, restart the game (or Windows when the toggle says so) and repeat both
   measurements.

## `WindowedGameOptimizations`

This toggle controls Settings > System > Display > Graphics > Optimizations for windowed
games. Windows moves DirectX 10 and 11 games that run in windowed or borderless mode from
the blit presentation model to the flip model. This lowers latency and allows variable
refresh rate and Auto HDR in those modes. Games that already use the flip model, and
exclusive fullscreen games, are not affected.

| State | What it does |
| --- | --- |
| Enable | Sets `SwapEffectUpgradeEnable=1` in `HKCU\Software\Microsoft\DirectX\UserGpuPreferences\DirectXUserGlobalSettings` for the current user. |
| Disable (default) | Removes only that entry, so Windows decides again. Some systems turn the feature on by default and some do not. |

The other entries in the same string (Auto HDR, variable refresh rate) are kept. A plain
registry entry would replace the whole string, which is why the toggle uses companion
functions. Each new account gets the choice at its first sign-in. No restart is needed;
restart the game.

**Measure:** run PresentMon on a borderless DirectX 11 game. The `PresentMode` column moves
from `Composed: Copy with GPU GDI` to a flip mode (`Composed: Flip` or
`Hardware: Independent Flip`). Compare the average and 99th-percentile frame time and the
display latency.

## `ProcessorPerformancePreference`

Energy performance preference (EPP, 0 to 100) tells a processor with hardware-controlled
performance states (Intel Speed Shift, AMD CPPC) how readily to raise its clock: 0 favors
performance and 100 favors energy saving. EPP is a power-plan setting, so it belongs to
the active plan. Windows also keeps a second value (`PERFEPP1`) for the efficiency cores
of hybrid processors.

| State | What it does |
| --- | --- |
| Enable | Sets both AC values to `0` on the active plan. This is the value the Windows High performance plan uses. |
| Disable (default) | Sets both AC values back to the Windows default for the active plan, read from `PowerSettings\...\DefaultPowerSchemeValues`. The Atlas plan and other copies of a Windows plan get the Balanced default (`33`). If Windows records no default, nothing is written. |

Battery (DC) values and every other processor setting stay as they are. Core parking,
boost mode and throttle states are already set by the Balanced copy that `PowerSaving`
applies. Minimum processor state is left alone: raising it keeps the clock high at idle,
which costs power and heat for little gain. `PowerSaving` applies the recorded choice
again after it switches or rebuilds the plan. No restart is needed.

**Measure:** `Measure-AtlasPerformance` records the active plan's processor values
(`power.processor`) and the average processor performance percentage
(`memory.cpuPerformancePercent`). Run it at idle, then run PresentMon in a CPU-limited
scene. Compare the p99 and average frame time and `MsCPUBusy`.
