# AFTERWARD — Storyline & Plot Bible
*Derived from the Game Design Document (Oct 23, 2026). Written to be pasted into a coding chat. Target engine: Godot 4.x (2D top-down).*

Items marked **[LOCKED]** come straight from the GDD. Items marked **[PROPOSED]** are my gap-fillers; the GDD left them open. Change them freely.

---

## 0. One-paragraph plot

Verenholt is a fantasy kingdom that retells the same story forever: a Hero rises, a Villain falls, everyone else is scenery. When the story ends or breaks, the world resets. Only the Hero's progress survives. Pell, a junior Custodian, is the one who cleans up behind the Hero (restocking pots, re-hiding treasure, dragging goblins back to spawn). Pell wakes up remembering yesterday. Over about 40 loops Pell learns that the world is a story that **casts** whoever behaves most like each role. The Dark Lord was a cleaner, and before that a Hero. The Hero was the cleaner before Pell. Pell is being **auditioned** for a bigger part. In fiction, Verenholt is a game and the Hero is a **Player's** character. The Player is never shown. Pell must decide which part to play, or whether to end the casting.

**Tone:** funny on the surface, sincere underneath. The jokes are about RPG tropes; the heart is being forgotten every morning.

---

## 1. Setting & fiction rules **[LOCKED]**

| Rule | Detail |
|---|---|
| The Cycle | One Cycle = one loop. Dawn at the same village inn. The Hero wakes, takes the same first quest, and sets off. The Guild follows. |
| Reset trigger | Story **ends** (Villain falls) or **breaks** (Hero dies, or Cycle timer runs out). |
| What persists | Hero's level, items and map. Everything else resets. |
| The Casting | Nobody runs it. Before each telling, the story recasts any empty role with whoever behaves most like the part. Roles: Hero, Villain, Mentor, shopkeepers, scenery. |
| Default rotation | A Hero who wins is recast as the next Villain. The old Villain is wiped to a forgettable Custodian. A remembering cleaner becomes the next Hero. Players learn this as "roles rotate" in acts 1–3. In act 4 they learn it can be broken. |
| Why Pell remembers | The story has started auditioning them. A moment of real kindness or cruelty from the Hero broke the script and made Pell visible. |
| The Player | Someone outside the game keeps starting runs. The Hero is their character. Greed/Violence/Mercy drives are their playstyle. Resets are them dying or reloading. The Hero keeps progress because the save file does. Never shown or named. NPCs feel them only when the Hero **freezes** (inn, mid-quest) for hours while the world politely waits. |
| No Hero, no world | Verenholt only runs while a Hero loops it. Nothing continues without one. |

**Never** parody a specific game. Satirise broad tropes and player behaviours only.

### Regions
1. **Thornbury** (village) — pots, crates, chickens, the inn
2. **Gloamwood** (forest) — camps, traps, wildlife
3. **Deepvein** (mines) — collapsed tunnels, goblin warrens, Mara's shop fire
4. **Aurelle** (capital) — arena, noble houses, siege, the Archivist's library
5. **The Tower** — the Dark Lord's quarters
- **Hub:** Guild Hall (dormitory, workshop, Supervisor's office, stash)

---

## 2. Cast

| ID | Character | Story function |
|---|---|---|
| `pell` | **Pell** (protagonist, junior Custodian) | Dry, tired, observant. Text-only monologue. Arc: Numb → Awake → Empowered → Decided. |
| `hero` | **The Hero** | Utility-AI "player". Drives: Greed, Violence, Mercy (0–100). Awareness of Pell: Oblivious → Curious → Suspicious → Engaged. |
| `bramm` | Supervisor Bramm | Guild boss, pressure on Suspicion. **Secretly half-remembers.** |
| `tilly` | Tilly | Cheerful, oblivious Custodian. First Awakening target; emotional anchor. Final loop: she sweeps behind Pell and waves. |
| `innkeeper` | The Innkeeper | Early info on Hero habits. First to call Pell "hero" in the recast loop. |
| `mara` | Mara the blacksmith | Workshop and crafting. Her shop is destroyed in act 3 every Cycle. |
| `grub` | Grub (goblin) | Reset every morning. Comic relief. Tutorial for monster recruiting. |
| `mayor` | The Mayor | Corrupt. Pays the bandits. Overlord leverage. |
| `archivist` | The Archivist | Keeps the record of every past casting. Reveals the rotation in act 4. |
| `wenna` | Old Wenna | Former rememberer, "mad". Mentor/warning. Was offered a role and **refused**. |
| `dark_lord` | The Dark Lord (she) | Former Custodian, before that a Hero. Pell's foreshadowed future. |
| `prev_cleaner` | The Hero's old Custodian self | Not on screen. Found through the locker, handwriting and broom. |

---

## 3. The central mystery (the player's question ladder) **[LOCKED]**

Each question maps to a Journal reveal. Use these as `mystery_*` flags.

1. `mystery_why_remember` — Why do I remember when no one else does?
2. `mystery_who_casts` — Who decides who plays which part?
3. `mystery_hero_person` — Is the Hero a person or whoever fits?
4. `mystery_hero_wins` — What happens if the Hero ever wins for good?
5. `mystery_past_cleaners` — What happened to the cleaners who remembered before me?

---

## 4. Act-by-act plot

Loop counts come from the GDD's pacing targets (~40 loops in a first playthrough).

### Act 1 — "The Pots" · Thornbury · loops 1–3 *(Numb)*
- **Opening.** Dawn in the Guild dormitory. Pell sweeps up after the Hero smashes the inn's pots. Pell assumes yesterday was a bad dream.
- **Loop 2 hook.** Pell *remembers loop 1*. The Hero does the same thing again. The monologue lands the premise ("He kicked down a door that was unlocked. I know. I unlocked it.").
- **Tutorial beats.** Restock, repair, reset a goblin (**Grub**), first Supervisor inspection (**Bramm**), first stash (Depth 2).
- **Rebirth dream #1.** First *Audition*: Pell on the Scenery card. Silhouette flickers for one second, unexplained.
- **Exit:** Memory Depth 1 → 2.

### Act 1–2 — "Learning the Hero" · Thornbury → Gloamwood · loops 4–10 *(Awake)*
- Player learns the Hero's habits (waterfall checks, chest order) and banks loot in the first stash.
- **Hero tier-2 gear** begins appearing as leftovers (bows, herb kits, bombs).
- **First rotation clue:** a faded Guild staff portrait with one face scratched out. A Memory Fragment there shows a cleaner in Pell's uniform climbing the Tower steps.
- Wenna's first appearance: cryptic, treated as mad.
- Leanings are hidden. The world gives soft feedback only.
- **Exit:** Depth 3 (can sense Seams, build more stashes).

### Act 3 — "The Locker" · Deepvein mines · loops 11–22 *(Empowered)*
- **Midpoint dream.** The Audition names Pell's dominant Leaning (path): Overlord / Villain / Pacifist / Lover. Pell's silhouette leans toward Hero or Villain. Player may lean in or start shifting.
- **Mara's shop burns** every Cycle. Workshop access becomes a scheduling puzzle.
- **The Hero's old Custodian locker** (mines or Guild Hall): their handwriting, their broom, notes about *their* Hero. The Journal opens the **Casting tab**.
- First Awakening candidate: Tilly (Fragment + Bond 4).
- Pell can now afford real fights with Hero-tier iron and steel leftovers.
- **Exit:** Depth 4 reachable (Awaken NPCs).

### Act 4 — "The Records" · Aurelle (capital) · loops 23–32
- Tournament, siege, arena. Disguises, forged papers, social access.
- **Archivist reveal.** The rotation: winners become Villains, Villains become cleaners, remembering cleaners become Heroes. And it can break: **one past Villain never showed up.**
- Hero Awareness of Pell becomes visible. The Journal starts telegraphing the Hero's turn ("He's been asking the Mayor about taxes"). *The Hero's reaction must read clearly as cocky or angry well before act 5, or it will feel random.*
- Permanent Changes (a rebuilt bridge, a broken wall).
- Guild attention rises per Awakening. Too many Awakened NPCs and the story starts recasting them.
- **Exit:** Depth 5 reachable (see the Cycle's machinery; endgame choices open).

### Act 5 — "The Empty Throne" · The Tower · loops 33–40 *(Decided)*
- Pell gets ahead of the Hero and reaches the Dark Lord first. Three methods:
  - **Defeat** (Defiance): multi-loop boss prep, traps, armed Grub, the Hero's discarded legendary gear.
  - **Trick** (Control): forge a summons that sends her away.
  - **Befriend** (Compassion/Charm): carry items from her old locker over several loops until Bond 4. Hardest and most moving.
- **The Hero finds the Tower empty.** Reaction by strongest drive:

| Hero drive | Reaction | Result |
|---|---|---|
| Greed | Sits on the throne, laughs, crowns self | Next loop: tax collectors in the village, Hero's banner on the Tower. Recast as **Villain (tyrant)**. |
| Violence | Tears the Tower apart for a fight, turns on villagers | Recast as **Villain (rampager)**. |
| Mercy | Sets the sword down on the steps and walks home | **No recast.** Leads to **The Kind Hero**. |

- **If the Hero turned:** the next dawn breaks the 40-loop pattern. Pell wakes in the **Hero's bed** at the inn, the sword against the wall. The Innkeeper says "hero" for the first time. One final loop **as the Hero**. A Custodian sweeps up behind Pell (Tilly, if Awakened, waves). The final fight is the old Hero, now Villain, in the Tower Pell cleaned a hundred times. **Pell's Journal of their habits is the boss guide.**

---

## 5. Path storylines (hidden Leanings 0–100, never decrease)

| Path | Leaning | Story fantasy | Signature | Hero ends up |
|---|---|---|---|---|
| **Overlord** | Control | Every quest the Hero took, Pell wrote | **The Web** (NPC network) | A tool who eventually realises it was played |
| **Villain** | Defiance | One massacre too many; gear up from the Hero's scraps | **The Lair** (hidden base in a Seam) | Learns to fear and hunt Pell |
| **Pacifist** | Compassion | They don't know what they're breaking. Show them. | **Empathy** (hidden Hero stat) | Shifts to Mercy, asks to meet Pell |
| **Lover** | Charm | Forty deaths in your arms; never once known your name | **Affection** (resets per Cycle until Soulmate) | Blushes, protects, finally remembers |

- **Second-strongest Leaning** adds flavour only (an extra scene, final conversation, epilogue). Examples: Lover + Defiance = *Rivals to Lovers*; Lover + Control = *The Schemer's Heart*; Villain + Compassion = spares the Hero; Overlord + Charm = rules alongside the Hero.
- Abilities: 3 tiers each; tier 3 needs that path dominant.
- Act 1–2 hidden → Act 3 midpoint dream names the path → Act 5 final choice.

---

## 6. Endings

Every ending is a casting. Each has an epilogue showing 6–10 NPCs.

| ID | Ending | Requires | Outcome |
|---|---|---|---|
| `end_last_boss` | **The Last Boss** (basic) | Beat or trick the Hero in direct encounter; any path | Audition prompt: *Take the part?* **Yes:** Pell wakes in the Tower in Dark Lord armour, plays one loop as final boss, credits. **No:** Pell refuses like Wenna, loses that loop's unbanked memories, continues; offer returns later. |
| `end_puppet_king` | **The Puppet King** | Overlord dominant | Pell rules from the shadows and casts every role. The story runs on. |
| `end_kind_hero` | **The Kind Hero** | Pacifist dominant; Dark Lord befriended; Mercy Hero | Hero hangs up the sword. No role is empty. |
| `end_afterward_happily` | **Happily Ever Afterward** | Lover dominant, Soulmate unlocked | The Hero remembers Pell and refuses the role. Bittersweet variant if the Hero never fully remembers. |
| `end_new_hero` | **The New Hero** | Villain role vacated, Hero recast as Villain | Pell is cast as Hero and defeats the person they cleaned up after. |
| `end_true` | **Afterward** (true) | Depth 5, all four Leanings > 40, Dark Lord's history uncovered | Pell accepts the Hero role *without* forgetting, remembers everyone holding the story up, and with every Awakened NPC ends the casting. |

### ⚠ Open: three endings conflict with "No Hero, no world" **[LOCKED rule, PROPOSED fixes]**
The GDD flags that *The Kind Hero*, *Happily Ever Afterward* and *Afterward* (true) end or stall the loop, but the world can't continue without a Hero. Suggested reframes, so each remains about **who the Hero is and how the loop runs**:

- **The Kind Hero.** The Player stops playing a *conqueror*. The loop becomes a gentle one: the Hero (now Mercy-driven) wanders Verenholt without conflict, helping people. The story "ends" as an epic and becomes a slice-of-life that never needs a Villain. World keeps running because the Hero keeps wandering.
- **Happily Ever Afterward.** The Hero remembers Pell and, when the Player tries to start a new run, the Hero **refuses to reset**: they stay at the inn. The world pauses politely (the same "freeze" NPCs already know). Pell and the Hero have a life inside the pause. End on the Hero turning to Pell: "What do we do now?"
- **Afterward (true).** Pell takes the Hero role, remembers everything, and uses the Hero's one power (progress survives the reset) to carry every Awakened NPC's memory across. The Player's next run starts with a Hero who *won't follow the script*. The casting ends because the Player has no one left to cast as scenery.

---

## 7. Memory Depth & Audition (story pacing hooks) **[LOCKED]**

| Depth | Story meaning |
|---|---|
| 1 | Fragmentary memory of the last Cycle |
| 2 | Full memory; first stash |
| 3 | See Seams; more stashes |
| 4 | Awaken NPCs |
| 5 | See the Cycle's machinery; endgame choices |

**The Audition** (rebirth dream): dark stage, role cards above (Hero, Villain, Mentor, Scenery). Pell starts under **Scenery**. Silhouette drifts nightly. Fighting/sabotage → Villain. Protecting people while the Hero turns cruel or cocky → Hero. Doing little → stay. Act 4 reveals what it was. When a role is offered: *Take the part?*

---

## 8. Story-state flags (suggested for Godot)

Use a single autoload `StoryState` holding a `Dictionary` of booleans/ints, serialised in the Dawn autosave.

**Progress**
`loop_count:int`, `hero_act:int (1–5)`, `memory_depth:int (1–5)`, `cycle_phase:enum`

**Leanings** — `lean_control`, `lean_defiance`, `lean_compassion`, `lean_charm` (0–100, monotonic)

**Hero** — `hero_greed`, `hero_violence`, `hero_mercy` (0–100), `hero_awareness (0–3)`, `hero_empathy`, `hero_affection`, `hero_remembers_pell:bool`

**Pell** — `audition_card:enum(scenery|mentor|villain|hero)`, `guild_suspicion (0–100)`

**Revelations** — `mystery_why_remember`, `mystery_who_casts`, `mystery_hero_person`, `mystery_hero_wins`, `mystery_past_cleaners`; `found_locker`, `found_archivist_records`, `knows_rotation_breaks`, `knows_dark_lord_was_cleaner`, `knows_player_exists`

**NPCs** — per-NPC `bond (0–5)`, `awakened:bool`, `fragment_found:bool`

**Dark Lord** — `dark_lord_state: enum(present|defeated|tricked|befriended)`, `dark_lord_bond (0–4)`

**Casting** — `hero_recast_as: enum(none|tyrant|rampager)`, `pell_role_offered`, `pell_role_refused_count`

**Endings** — `ending_unlocked: Array[String]` (persist for New Game+)

### Suggested beat triggers
- Beat fires when `loop_count`, `hero_act`, `memory_depth` and flags match its `requires` block.
- Beats are `Resource` files (`StoryBeat.tres`): `id, requires, once, dialogue_id, journal_entry_ids, set_flags`.
- Dreams and the Audition are a separate scene triggered on every reset.

---

## 9. MVP slice (story-wise) **[from GDD §21]**

| Release | Story content |
|---|---|
| **1. One shift** (itch.io) | The inn only. Scripted Hero, ~10 loops, one secret, one ending. Hits: loop-2 "I remember", silhouette flicker, stash survives reset. |
| **2. One village** | Thornbury + Guild Hall menu. One path (Pacifist or Lover), 5–6 NPCs, Suspicion, two endings (e.g. `end_kind_hero` + `end_last_boss`). |
| **3. First chapter** | + Gloamwood, two paths, first rotation clue (scratched portrait), Dark Lord twist teased. |

---

## 10. Items I filled in (please review)
1. The three ending reframes in §6.
2. Act titles ("The Pots", "The Locker", "The Records", "The Empty Throne").
3. Where the locker sits (mines is where the GDD places it; the Guild Hall is an alternative).
4. The flag list and the `StoryBeat` resource structure in §8.

## 11. Still open in the GDD (not resolved here)
Does Pell age visually · hard loop cap? · fixed vs randomised Hero · can Pell speak to the Hero before act 4 · death vs timer as the main reset trigger · co-op · Awakening darkness / rating · pixel vs hand-painted · final title.
