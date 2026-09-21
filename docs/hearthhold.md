# Hearthhold (removed, kept as design material)

> **This game was deleted on 21 September 2026.** It is kept because the thinking in it is the useful
> part - why a guided game needs a reason to do each thing, in an order that makes sense, with someone
> to do it for - and that reasoning should feed whatever guided game 1.0 ships. The code is in the
> history; the models it used are in `art/models/hearthhold/`.


A second game alongside vanilla: the guided one. Vanilla stays the open sandbox — this is the one that
gives a child a reason to do each thing, in an order that makes sense, with someone to do it for.

## 1. The problem it solves

The five things a player can do are in very different shape today:

| Pillar | Today | What this game gives it |
|---|---|---|
| Crafting | Deep: discovery, stations, tiers, parts, traits, quality minigames, co-op | Stays as it is, and becomes the means rather than the end |
| Combat | Night-time nuisance; you fight what comes to you | A reason to go looking, and something of yours worth defending |
| Exploration | Biomes and structures with no reason to travel | Named places, at real distance, holding people and things found nowhere else |
| Building | No mechanical payoff at all — the game never cares what you built | The gate on everything: people need homes, and homes are what you build |
| Questing | Real, but siloed in an optional add-on nobody opens | The spine, given by people who live with you |

The imbalance is not a shortage of content. It is that crafting is a loop and the other four are flat.

## 2. The spine

You arrive alone at a ruined outpost. **People are out there, stranded and hiding. You find them, bring
them home, and build them somewhere to live. Each one you settle makes the place more capable.**

That single sentence has to carry every pillar, and it does:

- **Build** a dwelling, and someone can live in it. Building becomes the limit on how many people you can
  bring home — the thing children already spend their hours on is now the thing the game counts.
- **Explore** to find them: each is at a named landmark, far enough away to be a journey.
- **Fight** to reach them, and later to keep what you have: the settlement draws attention at night, and
  how much attention depends on how big it has grown.
- **Craft** because each settler opens a part of the crafting tree — the cook the pot, the smith the
  forge line, the scout the maps.
- **Quests** come from the settlers themselves, in their own voices, about things they need.

## 3. The pieces

### 3.1 Dwellings, and why building is the gate

A dwelling is not detected by invisible room rules — a child would never work those out. It is a
**Hearthstone** you place, which checks what is around it and tells you plainly what is missing:

```
  Hearthstone
  ✓ A bed within 6 blocks
  ✓ A door
  ✗ A light (a torch or a lamp)
  ✓ A roof over the bed
  → Someone could live here once it has a light.
```

Requirements are a checklist on a panel, ticking as you build. No guessing, no "why is it not working",
and it teaches the parts of a house by naming them.

### 3.2 The settlers

Each is a person with a name, found somewhere specific, who follows you home and settles into a free
dwelling. What each one opens should be something the player already half-wants by the time they meet them.

| Settler | Found | Opens |
|---|---|---|
| **The cook** | A cold camp in the woods | The cooking pot, and meals with effects |
| **The smith** | Trapped in a mineshaft | The forge line, and tool parts without hunting for plans |
| **The scout** | On a watchtower | Landmarks appear on your map, and points at what is worth walking to |
| **The healer** | A ruin in a bad place | Bandages, and the settlement heals while you sleep |
| **The builder** | Under rubble | Better blocks, and a second wave of dwelling parts |
| **The keeper** | Last, and hardest | The beacon, and the ending |

Six is enough for an arc a family can finish over a few weekends.

### 3.3 The charter board

One block in the middle of the outpost, showing what the settlers need right now, in their words. This is
the quest system generalised out of `guild` and into the engine, so any game can use it.

### 3.4 Night pressure

The more people live here, the more attention the place draws. Pressure is a number that rises with the
settlement's size and falls with its walls and lights, so a child can *see* why tonight is harder and what
to do about it. Never enough to wipe the place out — settlers hide, they do not die.

## 3a. The story

Deliberately small. Four chapters, an evening or two each, no branching, no cutscenes, and not one wall of
text. It is told three ways: **what you find** (a camp with two bowls still on the stones), **what people
say when you meet them** (three lines, never more), and **pages that fill in the guide book as you go** —
the book is the storybook, and it writes itself while you play.

**The premise.** Quarrowen was a working valley: a quarry, a road, and a light at the heart of it that
kept the dark thin. One long night the light went out. Nobody agreed on why. People took what they could
carry and scattered into the hills, meaning to come back when it was over, and it was never quite over.

You arrive after all that, on the road, with nothing. The outpost at the valley mouth still stands.

### Chapter 1 — The Cold Hearth

Alone. The hearth is out and the wall has a gap in it. The charter board still hangs there with the last
warden's handwriting on it, asking for firewood — a note written to someone who never came.

You light the fire. You survive a night. That is the whole chapter, and it should take about an hour.

*The change:* the fire is lit, and it is yours. The guide's first page appears: **"Someone kept this place
once."**

### Chapter 2 — The Long Way Home

Smoke carries. In the morning there is a mark on the board that was not there before — someone saw the
fire from a long way off and left directions to a cold camp in the woods.

You walk out and find **Bramble**, a cook who has been eating badly for a long time and will not stop
apologising for the state of the place. She follows you home if you can promise her a roof.

She cannot stay in a field. She needs a *house* — and so the Hearthstone checklist appears, and the game
quietly teaches walls, a door, a bed and a light by making a person want them.

*The change:* you are not alone, and the pot goes on. The valley now has one chimney.

*This is the chapter that decides whether the game works.* If walking her home is tedious, everything
after it is built on sand.

### Chapter 3 — Six Chimneys

Bramble remembers the others. Not where they are — she is not a map — but who they were, and what they
were like, which is enough to know a place when you see it.

- **Cobb**, a smith, trapped behind a fall in an old mineshaft. Gruff, embarrassed to be rescued, hands
  you a hammer as an apology. *Opens the forge line.*
- **Wren**, a scout, living on a watchtower because she can see everything from it and trusts nothing.
  *Puts landmarks on your map.*
- **Odd**, a healer, in a ruin in a bad spot, treating people who never arrive. *The settlement mends
  while you sleep.*
- **Mab**, a builder, under rubble she caused herself and entirely unrepentant. *Better blocks, bigger
  houses.*

Each wants a house. Each house is one more chimney, and the valley starts to look inhabited from the ridge.

*The change:* the place is worth something now — which is exactly when the nights get harder. The dark has
had this valley to itself for a long time, and it notices smoke.

### Chapter 4 — The Light Returns

The last one is **Tam**, the keeper, who has been sitting in the dark at the bottom of the quarry since the
night it went out, because somebody had to stay. He knows how the light is lit. He has known all along. He
could not do it alone, and would not ask anyone to come down there with him.

The finale is not a boss with a health bar you whittle. It is **one long night while the light comes back
on**: you and the settlers you brought home, the walls you built, the food Bramble cooked, the tools Cobb
made — all of it tested at once, for as long as it takes. Everything you did is the reason you survive it.

Then the light catches, and it holds.

*The change, and the ending:* the nights go quiet for good. The valley is settled. The guide's last page is
the first one again, rewritten: **"Someone keeps this place."**

### After the ending

Nothing is taken away. The world stays, the settlers stay, the light stays lit, and a child who just wants
to build a enormous house on the ridge now has six people who will comment on it. Any remaining charter
tasks become small, cheerful, endless ones — a delivery, a repair, a request for more pie.

### Tone rules, for anyone writing more of it

- The antagonist is **the dark**, and it is weather, not a villain. It has no name, no face, and no motive.
- Settlers are hurt and hide. **Nobody dies.** A child who walked three hundred blocks for Bramble must
  never lose her.
- Three lines each, maximum. If a settler needs a paragraph, it belongs on a guide page instead.
- Everyone is a bit funny and a bit useless at something. Nobody is noble.
- It is a story about **coming back and staying**, not about winning.

## 4. What the engine already does, and what is missing

Most of this exists. Listed honestly, because the missing pieces are the real cost:

**Exists:** entities with AI, pathfinding and persistence; server-driven UI panels (dialogue is a panel);
multiblock detection (the Forge); world markers on the shared map; loot tables with conditions; stations
and tiers; the guide and tutorial systems; taming and following behaviour for wolves.

**Missing, and worth building because every mod gets them:**

1. **A follower that behaves.** Paths to you, waits when you stop, does not drown in a river, teleports if
   badly stuck. Extends the existing mob brain rather than replacing it.
2. **Dialogue.** A panel with a portrait, a line, and two or three replies. Data, not code, so a mod
   writes conversations as JSON.
3. **Quests in the engine.** `guild`'s system, generalised: offer, accept, track, complete, reward.
4. **A place-checker.** "What is within N blocks of this block, and does it satisfy this checklist?" —
   what the Hearthstone needs, and what any base-building mod would want.

## 4a. On covering the whole engine

Tempting, and wrong as a goal. A game built to exercise every capability becomes a tech demo: a child
feels content that exists because the engine can, rather than because the story wanted it. The story
decides; coverage is the project's problem, not this game's.

That said, the design earns most of it without trying:

| Capability | Where the story already wants it |
|---|---|
| World markers on the shared map | Wren the scout, marking what is worth walking to |
| Loot tables, conditions, rare finds | What is left at each rescue, and in the quarry |
| `roll_loot` from code | Caches, and the charter's rewards |
| Structures and templates | The camp, the mineshaft, the watchtower, the ruin, the quarry |
| Multiblock detection | The Hearthstone's checklist |
| Server-driven UI | Dialogue, the checklist, the charter board |
| Entity AI, pathing, persistence | Settlers who follow you home and then live there |
| Stations, tiers, quality minigames | Cobb opening the forge line; Bramble the pot |
| Food effects, healing | Bramble's meals; Odd mending the place while you sleep |
| Spawn caps and rules | Night pressure rising with the settlement |
| Guide pages and tutorials | The book as the storybook, filling in as you go |
| Cosmetics | A charter cloak, given once the light is lit |
| `explode` | Mab clears rubble, which is how she ended up under it |
| Sounds and effects | The hearth, the light catching |

What it does **not** reach, and should not be bent to reach: the JavaScript sandbox (`guild` is the proof),
power networks (`industry`), server-to-server portals, player creations and moderation, custom equipment
slots, and the one-block and island modes. Those belong to other mods and to `examples/`, which is exactly
why the catalogue keeps them rather than folding everything into one flagship.

The rule: **if a capability has no home in the story, it needs an example, not a shoehorn.**

## 5. Order of work

Each phase is playable on its own, which matters: the family can try it early and say what is dull.

- **Phase 1 — the vertical slice: chapters 1 and 2.** Arrive at the ruin, light the hearth, survive a
  night, walk out to the cold camp, bring Bramble home and build her a house. Everything the game is
  resting on is in that hour: the Hearthstone checklist, a settler who follows, and whether the walk back
  is a journey or a chore. If escorting her home is tedious the design is wrong, and it is better to know
  that after a week than after three months.
- **Phase 3 — the others.** The remaining settlers, their dialogue, what each opens.
- **Phase 4 — nights that mean something.** Pressure, walls and lights that answer it, the keeper, the end.

## 6. Still open

- **Do settlers die?** Recommendation: no. They are hurt and hide; a child who loses a person they walked
  three hundred blocks for will not come back to the game.
- **Multiplayer.** Whose settlement is it? Simplest: one shared settlement per world, and anyone can bring
  someone home. Siblings cooperating rather than each keeping a private village.
- **How long is the arc?** Aim for a few weekends, not a summer.
