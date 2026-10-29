# GridKit Roguelite Implementation Plan

Goal: Add a three-floor real-time survival run while retaining all five puzzle levels.
Architecture: Grid, GridEntity, TickManager and the X/Z cell mapping remain shared. Level.build consumes ASCII maps in both modes. Existing Player and Enemy gain mode-gated combat; Level owns navigation and pickups. A run controller manages floors and a separate HUD owns paused choices.
Tech: existing Summer/GDScript, existing textures/sprites, no generation or external addons.
Recovery: backups/gridkit-before-roguelite-20261029.zip contains pre-change project sources and assets. No .git directory exists.

- [x] Phase 1: scripts/roguelite/dungeon_generator.gd, run_state.gd, profile.gd. Seeded connected room/corridor maps with @, E, T, +, >. Flood-fill validation requires one spawn and exit, all floor cells reachable, and safe enemy spawns. Test seeds 0..99 on floors 1..3, determinism and fallback.
- [x] Phase 2: Extend player.gd, enemy.gd, level.gd and visuals.gd. Preserve puzzle branches. Add HP, cooldown combat, LOS, grid BFS, health/XP drops and gated exit. Check each affected script in editor.
- [x] Phase 3: scripts/roguelite/run_controller.gd and hud.gd. Add floors, six upgrade types, pause/terminal overlays, HUD and restart/menu flow. Connect from GameManager, GameFlow, LevelManager and main menu. Persist profile/settings through validated ConfigFile data in user://.
- [x] Phase 4: Run editor checks for every script; live input/probe playtests for both modes, damage/invulnerability, upgrade pause, floor progression, death/victory/restart, persistence and LOS. Inspect screenshot and debugger evidence; record limits honestly.

Puzzle maps, renderer, existing autoload registration and scenes remain unchanged. Roguelite uses top-down, four-direction physics movement and the sprite, without altering Puzzle preferences.
