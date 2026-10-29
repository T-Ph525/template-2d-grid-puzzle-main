# GridKit — seed 101, navigation and pacing report
Updated 2026-10-30. Project D:/template-2d-grid-puzzle-main, Summer Engine 0.8.3.

## Current state
The seed-101 timeout is fixed. It was a moving-target grid replanning cycle, not insufficient combat damage, wall collision, or a timeout that needed extending.
A separate production-enemy version of the boundary oscillation was reproduced with a failing regression and fixed.
All six final test seeds won three floors through normal movement, automatic combat and offered upgrades.
No controlled clears, teleports, HP/XP grants or stat edits were used as normal-victory evidence.
The bot timeout remains 240 simulated seconds.

Normal play: Play -> Roguelite — New Run; optional numeric seed.
WASD/arrows move, attacks are automatic, blue orbs grant XP, red orbs heal. Choose upgrades, clear enemies and enter the green exit; clear floor three to win.
Esc pauses; R restarts the same seed. Both Puzzle entries retain the five original puzzles.

## Reversible checkpoint / preservation
Before edits, created and reopened backups/gridkit-before-seed101-navigation-20261030.zip (111 source/scene/configuration files; no art changes).
Earlier backups remain. No Git repository exists; the archive is the reversible checkpoint. Close the editor before restoring.

Byte comparison confirmed unchanged: scripts/autoload/level_manager.gd (including all five ASCII LEVELS), scripts/roguelite/profile.gd, Grid, GridEntity, TickManager, InputRouter, Box, project.godot, game.tscn and all eight original menu scenes.
The isolated test profile and existing Godot/GDScript architecture are preserved.

## Priority 1 — reproduction and confirmed causes

### Bot feedback loop
Temporary diagnostics recorded player/enemy positions, velocities, collision contacts, path start/goal/next cell, BFS cost, line of sight, HP, attacks, hits, XP, enemy counts, floor/exit state and feedback counters.
The original policy reproduced the timeout: seed 101, floor 2, six enemies remaining, HP 100, 240 simulated seconds (53.637 wall seconds).
Collision contacts were zero, attacks stayed at 10, and neither side made net progress.

The saved frame trace shows the cause:
- Physics 6820: player (1.066667, 0, 3.466666), goal cell (4,4), next cell (1,4), action DOWN.
- Physics 6821: player (1.066667, 0, 3.533333), goal cell (4,3), next cell (1,3), action UP.
- Physics 6822–6823 repeat the same two states.
The bot rounded into the next row and immediately reversed its plan as the chased enemy crossed the opposite boundary.
The 240-second harness limit exposed the cycle; it did not cause it.

Fix: the bot commits to a cell-center waypoint until it reaches that point before replanning its moving target.
It also avoids treating enemies behind walls as immediate escape threats.
With gameplay unchanged, the bot-only fix completed seed 101 normally in 63.17 simulated seconds (14.748 wall seconds).
Evidence: tests/seed101-before-navigation.json, seed101-stall-trace.json and seed101-bot-waypoint-fix.json.

Diagnostics are opt-in on the test bot (diagnostic_logging); normal test runs have verbose tracing disabled.
tests/seed101_diagnostic.tscn explicitly enables bounded diagnostic capture. The retained stall trace is historical pre-fix evidence; the current code should not reproduce that cycle.

### Production enemy steering
A dedicated regression alternates the target across the same row boundary for 120 physics ticks.
Before the production fix, the enemy remained at (4,0,3.533717), with no X progress.
Equal-cost BFS directions used fixed direction priority; recalculating an unfinished turn every frame could reverse movement.
The fix completes actor waypoints and breaks equally short route ties using continuous distance to the actual target.
A blocked waypoint is invalidated/replanned, with a 0.5-second motion-stall retry rather than a teleport.
After the fix, the enemy reached approximately (1.1,0,4) in the same test.
Evidence: tests/roguelite-navigation-before.json and roguelite-navigation-after.json.

## Priority 2 — navigation / progression safety
The 12 navigation checks pass:
1. Seed-101 moving-target waypoint regression.
2. Enemy pursuit across a jittering row boundary.
3. Three enemies traversing a winding one-cell corridor.
4. Waiting without crossing a closed door.
5. Replanning after a door opens.
6. Disconnected procedural encounters replaced before actors spawn.
7. Unsupported/unresolved procedural gates replaced before spawning.
8. Replanning around a newly added obstacle.
9. Soft peer separation in an open room.
10. Peer steering preserves pursuit progress.
11. Distant tank sentries hold their rooms.
12. Approaching a sentry activates it once.

Procedural maps are validated again by RunController before Level.build; disconnected/invalid maps use the deterministic fallback.
Roguelite generation currently supports #, space, @, E, T, + and >. An unresolved generated gate is rejected rather than creating an unbeatable encounter.
This does not alter Puzzle door/key/plate mechanics.
No enemies are silently removed, killed or teleported to unlock exits.
Closed-door navigation waits and resumes when the route becomes available. Normal final runs recorded zero unreachable enemies at floor completion.
Room peer steering is soft and bounded; corridors remain nonblocking to avoid crowd deadlocks. This is not a full crowd simulation.

## Priority 3 — measurements and modest pacing changes

### Measurement definitions
- sim_seconds: active floor simulation time; excludes tree-paused upgrade selection.
- encounter_seconds: time while enemies remain alive, including approach between groups; not an isolated weapon-DPS measurement.
- wall_seconds / real_elapsed_seconds: actual monotonic elapsed time, independent of the fixed simulation clock.
- navigation_seconds: actual movement outside visible attack pressure (player range + 0.4).
- combat_movement_seconds: movement within that pressure region.
- blocked_seconds: intended movement with negligible actual displacement; measured from pre-collision commanded velocity.
- exit_travel_seconds: post-clear travel/collection before entering the exit.
- Damage received counts accepted damage after reduction; healing counts actual pickup healing, not max-health-upgrade healing.
- Kills, collected XP and chosen upgrades are event counts.
The full 18-floor dataset is tests/roguelite-pacing-measurements.tsv and the nested JSON in tests/roguelite-navigation-pacing-results.json.

### Controlled comparison
The navigation-fixed baseline ran all six seeds before pacing changes: all six won.
Across its 18 floors, mean time with enemies alive was 16.62 simulated seconds and mean post-clear travel was 7.38 seconds.

An initial sentry/spacing/recovery trial caused four deaths in six runs. It is saved as tests/roguelite-pacing-trial.json and is NOT a passing result.
That version was rejected: the added contact-recovery stop was removed and peer steering reduced from 0.35 to 0.12.
The bot was not granted health or made to select a special stronger build to hide those failures.

Retained modest changes:
- Existing purple tanks act as room sentries, waking once within five path cells or when damaged.
- A brief purple ring marks activation. The HUD explains that tanks guard rooms.
- Light lateral peer avoidance in open rooms; disabled in narrow corridors.
- Player speed, enemy speeds, all HP/damage values, XP rewards, upgrade values and spawn populations (8/11/14) are unchanged from the previous milestone.

Final mean time with enemies alive is 21.05 seconds; mean post-clear travel is 4.26 seconds.
Mean complete-run simulation time changed from 72.04 to 75.98 seconds.
These are small seeded bot samples, not human timing or a statistically isolated balance study.

### Complete normal-combat final runs
Fixed-fps 60, explicit seeds, normal stats/input/combat and legitimate upgrade selections.
All runs killed 33 enemies, collected 153 XP and chose six upgrades (two per floor).

| Seed | Outcome | Simulated seconds | Wall seconds | Accepted damage |
|---|---|---:|---:|---:|
| 42 | Victory | 72.48 | 15.838 | 48 |
| 101 | Victory | 73.35 | 16.293 | 72 |
| 2026 | Victory | 78.73 | 17.167 | 72 |
| 7 | Victory | 76.38 | 16.690 | 88 |
| 73 | Victory | 67.77 | 15.406 | 60 |
| 31415 | Victory | 87.17 | 19.933 | 222 |

Seed 101 per-floor measurements:

| Floor | Total sim s | Wall s | Encounter s | Damage | Kills | XP | Upgrades | Navigation s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 19.28 | 4.263 | 17.92 | 12 | 8 | 38 | 2 | 8.18 |
| 2 | 27.00 | 6.052 | 18.72 | 12 | 11 | 50 | 2 | 14.32 |
| 3 | 27.08 | 6.029 | 24.53 | 48 | 14 | 65 | 2 | 10.05 |

All 18 final floors recorded zero blocked-movement seconds and zero unreachable enemies at completion.
This does not prove arbitrary custom geometry or larger crowds cannot produce other stalls.

## Priority 4 — verification actually run
- All 40 GDScript files validated with Summer MCP: zero script errors.
- Main integration scene: 65 checks passed, zero failed, including all five original puzzle maps and mechanics, combat/XP/upgrades/healing, pause/death/victory, floor exits and telemetry event accounting.
- Navigation regression scene: 12 checks passed, zero failed.
- Normal start/restart/pause/menu flow scene: 8 checks passed, zero failed.
- Generation: 300 distinct seeds * three floors = 900 validated, repeat-deterministic maps; all three fallback maps also validated.
- Six complete normal-combat final victories: 42, 101, 2026, 7, 73, 31415. Controlled-clear integration fixtures are separate and never counted as normal victories.
- Runtime diagnostics on final bot/navigation/integration/flow tests: zero errors. Existing sprite-sheet integer-division and UI shadow warnings remain; the editor also reports the unrelated Blender import warning.
- Real profile hashes matched before and after every run:
  49494ce56eb3c40130a777bd3e2c1a4b627e6b03221a5e358d89c5b0ce47e3d7.
- All launched instances were stopped.

## Files changed in this update
- scripts/roguelite/playtest_bot.gd: stable waypoints, six explicit seeds, separate wall timing, opt-in bounded diagnostics, floor measurements in results. Timeout remains 240.
- scripts/level.gd: route tie-breaking, bounded room peer steering, sentry activation feedback and runtime floor metrics.
- scripts/enemy.gd: committed navigation waypoints, blocked-path retry, room-sentry behavior.
- scripts/player.gd: accepted-damage and actual movement telemetry only; no movement/combat-stat nerf.
- scripts/roguelite/run_state.gd: runtime-only floor_results; not added to the profile schema.
- scripts/roguelite/run_controller.gd: pre-spawn map validation/fallback, once-only floor snapshots, chosen-upgrade counters.
- scripts/roguelite/hud.gd: sentry hint.
- scripts/roguelite/verification.gd: four telemetry assertions, retaining the legacy/combat/save tests.
- New scripts/roguelite/navigation_verification.gd and tests/roguelite_navigation.tscn.
- New tests/seed101_diagnostic.tscn, seed101-before-navigation.json, seed101-stall-trace.json, seed101-bot-waypoint-fix.json, roguelite-navigation-before.json, roguelite-navigation-after.json, roguelite-navigation-baseline-metrics.json, roguelite-pacing-trial.json, roguelite-navigation-pacing-results.json and roguelite-pacing-measurements.tsv.
- Refreshed tests/roguelite-results.json, roguelite-flow-results.json, roguelite-script-validation.json and roguelite-generation-results.json.
- docs/roguelite-report.md and README.md.

## Safe testing
Normal gameplay still uses user://gridkit_profile.cfg.
Explicit test scenes select user://gridkit_test_profile.cfg; the HUD shows TEST PROFILE.
The one-way test-process guard still redirects stale profile objects to the test path.
Use tests/roguelite_safe_play.tscn for manual isolated play, roguelite_bot.tscn for six normal runs, roguelite_navigation.tscn for regressions, roguelite_verification.tscn for integration and roguelite_flows.tscn for menu/restart checks.
Alternatively pass the user argument --gridkit-test. Exit the game process to return to a normal profile launch.
Do not call tree-pause-changing gameplay methods while debugger GamePause suspension is active.

## Remaining limitations / next steps
- Human review is still needed for sentry readability, crowd feel, fairness, upgrade choices and fun. Automated successes do not mark those passed.
- The earlier 10–15 minute aspiration remains unmet: these bot runs last 68–87 simulated seconds. No movement slowdown or HP inflation was used to force that target. More authored encounters/exploration would be needed.
- Validated generation prevents initially unreachable enemies; runtime editor changes that permanently seal a room are not automatically undone. Closed-door reopening and dynamic-obstacle detours are covered.
- Larger crowd and low-power performance testing remain outstanding; current tests use the existing small spawn populations.
- There is still no added audio or between-launch run resume; statistics/settings persist.
No credits spent, paid generation, publishing or deployment.
