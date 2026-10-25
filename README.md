# NPC-game — *Afterward* (One Shift demo)

Godot **4.3+** prototype of the "One shift" milestone from the Game Design Document.
Open the folder in Godot (Project Manager → Import → `project.godot`) and press F5.
Everything is drawn in code (`scripts/main.gd`), no assets needed.

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Move |
| E / F | Primary / alternate action on the nearest thing (prompt shown at the bottom) |
| 1–8 | Use a satchel item (read letters, eat potions) |
| Tab | Memory Journal |
| Space | Fast-forward the Hero's passage |
| Enter | Advance phase / finish the shift |
| F1 | Debug: hidden Awareness, Leanings, Hero drives |

## The loop (one Cycle)
1. **Dawn** – plan.
2. **Hero's passage** – a scripted Hero smashes pots, kicks doors and the corner barrel, empties one chest, skips the other, clobbers Grub, and dumps old gear. Stay close enough to *witness* things (that is how Journal facts are learned), far enough not to raise his Awareness, or hide in the cart.
3. **Shift** – action budget equal to the number of work orders (story actions like talking, notes, gifts and reading the letter each cost 1 too, so plot choices mean skipping a chore; Strong Tea gives +2) vs. more work orders than actions. Restock pots/chests, repair the door, return Grub, pin a notice. Loot is free but risky: taking a chest's item leaves a *gap* unless you swap in a Scrap of Cloth.
4. **Inspection** – Supervisor Bramm scores Diligence, changes Suspicion (raid at 80+ confiscates the stash). Bribe him with coin.
5. **Rebirth** – everything resets except Journal, Memory Depth, Leanings, Hero state and the **stash in the Seam**. Items on you and coin are lost.

## Mechanics implemented
- Hero's progress = your progress: Hero act rises every 2 loops, so leftovers get better; gear in the Seam enlarges your satchel.
- Knowledge as keys: the barrel fragment only opens if you *saw* the Hero kick it; Grub only talks on a later loop.
- 3 Memory Fragments (barrel, Grub, the Hero's letter from loop 3+) → Memory Depth up (bigger stash) → ending.
- Hidden Leanings (Control / Defiance / Compassion / Charm) rise from what you do and pick the ending text; second leaning is the "blend".
- Hero drives (greed / mercy) shift from your notes and gifts and change his behaviour.
- Guild Suspicion and Hero Awareness meters with their consequences.
- Coin and the cheating Guild: wages arrive only at the end of the shift (itemised payslip: rent, broom rental, laundering, "misc. adjustment"), so at Memory Depth 1 coin is worthless after the reset. From Depth 2 you keep coin for one cycle (spend it or lose it) and the Journal/Pell expose how little the Guild actually pays. The Innkeeper's bar sells tea (+2 actions), bread (gift) and fakes; prices rise with the Hero's act while pay stays flat.
- Solid furniture: pots, chests, barrel, tables, cart and Grub block movement.
- Pixel-art look: the world is rendered through a pixelation shader (block size `PIXEL_SIZE` in `main.gd`, use a divisor of 1280 like 2, 4 or 5); text and UI stay crisp on a layer above.
- Two rooms (Inn + Kitchen) joined by the doorway at the south wall of the Inn; the Hero visits both, so you can only watch one room at a time.

## Not in the demo (see the GDD)
Real-time combat, adaptive Hero AI, multiple regions, NPC Bonds/Awakening, path ability trees, Web/Lair systems, save files.
