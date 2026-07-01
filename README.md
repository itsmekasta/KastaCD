**KastaCD** is a lightweight party cooldown tracker built for players who want instant awareness of their group's defensives, interrupts, and immunities without digging through a raid-cooldown spreadsheet mid-pull. Perfect for Mythic+ and Arena scenarios.

---

## Features

### Cooldown Icons
- Tracks 60+ class cooldowns across all 12 classes — defensives, immunities, interrupts, and offensive cooldowns
- Per-class spell selection with **Offensive / Defensive / Interrupt / Immunity** sub-tabs
- Icons anchor directly to party frames with adjustable position, offset, size, and icons-per-row
- Live cooldown and active-duration timers rendered on each icon
- Proc-style glow while a tracked ability is active; desaturation while on cooldown
- Optional icon borders toggle (cropped by default for a clean look)
- **PvP Medallion** tracking — optionally restrict to Arena/Battleground only
- Medallion always appears last in the icon row
- Spec-gated icons: spec-restricted spells (e.g. Rebuke for Retribution only, Skull Bash for Feral/Guardian only) are hidden unless the party member's spec is confirmed

### Interrupt Tracker
- Dedicated **Interrupt Tracker** bar — a separate, draggable anchor showing one class-colored bar per party member with an interrupt
- Progress bar fills as the cooldown recovers; empties on use
- Class icon on the left of each bar for instant identification
- Configurable **bar width**, **bar height**, and **font** (Friz Quadrata, Arial Narrow, Morpheus, Skurri) with **font size** slider
- Header shown only when unlocked; completely hidden when locked so the tracker is seamless in play
- Spec-gated: Holy Paladin won't show Rebuke; Balance/Resto Druid won't show Skull Bash

### Settings
- Content-type filtering — choose where tracking is active: Open World, Dungeon, Arena, Battleground
- Full profile system: create, switch, and delete named profiles; export/import setups as a copy-paste string
- Settings and Interrupt Tracker panels are **centred** in the content area for a clean layout
- All sliders include a **clickable value box** — click the number to type a precise value instead of dragging, supporting pixel-perfect positioning
- Clean dark settings menu via **/kcd**

---

## Slash Commands

| Command | Description |
|---|---|
| `/kcd` | Open the settings menu |

---

Built for **Legion 7.3.5**. No dependencies. No bloat. Just clean cooldown awareness.

![1](https://i.imgur.com/RODzcML.png)
