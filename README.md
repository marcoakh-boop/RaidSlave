# RaidSlave

A raid leader toolkit for **Turtle WoW** (1.12 vanilla client). Merges and streamlines features from Tactica (by Doite) and TankHelper into a single, no-nonsense addon — no boss tactic spam, no addon message flooding.

## Features

### Role Management
- Right-click any raid/party member to assign **Tank / Healer / DPS** roles (exclusive toggle)
- Role tags (T/H/D) displayed on raid roster and party frames
- **pfUI integration** — tank roles auto-sync to pfUI raid frames when SuperWoW is detected
- Preset Master Looter selection via right-click menu
- Optional whisper notifications when assigning roles

### Tank Assignment (8 tanks — Naxx-ready)
- Assign up to **8 tanks** with any combination of 8 raid target marks (Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star)
- Visual mark selection grid with icon highlights
- Custom text lines for extra callouts (polymorph, kite targets, etc.)
- **Scan Raid** button auto-populates tanks from your role assignments
- Broadcast assignments to Raid, RW, Party, Yell, or Say

### Movable Button
- Draggable button you can place anywhere on screen
- **Left-click** — dropdown menu to pick a channel and send tank assignments
- **Right-click** — open the Tank Assignment config panel
- Lockable position via `/rs options`

### Raid Builder
- Pre-configured raid composition defaults (tank/healer counts, size)
- LFM message generation with Soft Reserve / Hard Reserve fields
- Multi-channel announcements (World, LookingForGroup, Yell) with cooldown
- Auto-announce loop
- Save/load presets for different raids
- Discord and SR link posting

### Auto-Invite
- Keyword-triggered invites from whispers (e.g., `+`, `inv`, `dps`, `healer`)
- Automatic role detection from spec keywords (`prot`, `holy`, `fury`, etc.)
- Optional gear score check via whisper
- Auto party-to-raid conversion when group exceeds 5

### Composition Tool
- Import **Raid-Helper** (Discord bot) JSON compositions directly
- 3-step flow: JSON import, Discord-to-in-game name mapping, live group assignment
- Persistent name aliases across sessions
- Multi-split support for large raids
- "Sort Groups" applies the setup to your live raid roster

### Loot Management
- Auto-enables Master Loot when targeting a worldboss (raid leader only)
- Popup to switch loot method after boss loot is emptied
- Preset Master Looter auto-applied when ML is activated
- "Don't ask again this raid" option

### Export
- Export raid roster as tab-separated CSV (paste into Google Sheets)
- Format options: name only, name+class, name+role, name+class+role
- Optional column headers

## Slash Commands

| Command | Description |
|---|---|
| `/rs` or `/raidslave` | Show help |
| `/rs build` | Open Raid Builder |
| `/rs lfm` | Announce current LFM message |
| `/rs autoinvite` | Open Auto-Invite |
| `/rs comp` | Open Composition Tool |
| `/rs tank` | Open Tank Assignment |
| `/rs roles` | Post Tanks/Healers/DPS summary to raid |
| `/rs export` | Export roster as copyable CSV |
| `/rs rolewhisper` | Toggle whisper notifications on role change |
| `/rs clearroles` | Clear all role assignments |
| `/rs options` | Open options panel |
| `/rs loot` | Manually show loot method dialog |
| `/rspush` | Refresh role tag visuals |
| `/rsclear` | Clear all roles |
| `/rsai` | Open Auto-Invite (shortcut) |
| `/rs_pfui` | Show pfUI + SuperWoW detection status |

## Installation

1. Download or clone this repository
2. Place the `RaidSlave` folder into `Interface\AddOns\`
3. Restart the game or `/reload`
4. Disable Tactica and TankHelper if you had them — RaidSlave replaces both

## What was removed from Tactica

- **Boss tactics database** — 90+ built-in boss strategies and the entire posting UI. No more `/tt post` spam.
- **Addon message protocol** — all `SendAddonMessage` communication on the "TACTICA" prefix is gone. No more version pinging, role syncing to other clients, or loot notifications over the network.
- **Version broadcasting** — no more guild/raid version checks or update nags.

Role assignments are now **local-only** — only you see the T/H/D tags. This is by design for private server use where you're the raid leader and don't need to sync with other Tactica users.

## Credits

- **Doite** — original Tactica addon (role management, raid builder, auto-invite, composition tool, loot management)
- **Marco** — TankHelper, RaidSlave merge, cleanup, and 8-tank upgrade

## License

This addon is provided as-is for use on Turtle WoW. Based on Tactica by Doite.
