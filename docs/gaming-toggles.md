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
