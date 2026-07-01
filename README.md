**KastaCD** is a lightweight party cooldown tracker built for players who want instant awareness of their group's defensives, interrupts, and immunities without digging through a raid-cooldown spreadsheet mid-pull. Perfect for Mythic+ and Arena scenarios.

---

## Features

### Cooldown Icons
- Tracks 60+ class cooldowns across all 12 classes — defensives, immunities, interrupts, and offensive cooldowns
- Choose exactly which cooldowns to track, per class
- Icons anchor directly to party frames with adjustable position, offset, size, and icons-per-row
- **PvP Medallion** tracking — optionally restrict to Arena/Battleground only
- Spec-gated: spec-restricted spells (e.g. Rebuke for Retribution only, Skull Bash for Feral/Guardian only) only show once the party member's spec is confirmed

### Interrupt Tracker
- Dedicated draggable bar showing each party member's interrupt and its cooldown
- Configurable bar size and font/texture (SharedMedia-aware — pulls in whatever fonts/textures you have registered)
- Spec-gated: e.g. Holy Paladin won't show Rebuke; Feral/Guardian Druid tracks Skull Bash while Balance tracks Solar Beam

### Crowd Control Tracker
- Same as the Interrupt Tracker, but for stuns, roots, and incapacitates instead of interrupts
- Sorted by class, so party members of the same class are grouped together
- Baseline CC abilities show immediately; talent-choice CC (e.g. Mighty Bash / Mass Entanglement / Typhoon) appears once it's actually cast, since which one a player picked can't be known in advance

### Settings
- Content-type filtering — choose where tracking is active: Open World, Dungeon, Arena, Battleground
- Full profile system: create, switch, and delete named profiles; export/import setups as a copy-paste string
- Hovering any spell shows its cooldown, duration, spec requirement, and level

---

## Slash Commands

| Command | Description |
|---|---|
| `/kcd` | Open the settings menu |
| `/kastacd` | Same as `/kcd` |
| `/kasta` | Same as `/kcd` |

---

Built for **Legion 7.3.5**. No dependencies. No bloat. Just clean cooldown awareness.

![1](https://media.discordapp.net/attachments/324614870580461568/1521953043841548298/Screenshot_at_Jul_01_20-54-39.png?ex=6a46b4ba&is=6a45633a&hm=d94d0e689b92cc8d6a116c806360f96d03caaeb10b4e12fd2f4120e59cc46793&=&format=webp&quality=lossless&width=1342&height=1002)
![2](https://i.imgur.com/Yb5AZq8.png)
