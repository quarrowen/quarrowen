# Questions

## Is this Minecraft?

No. It is an independent voxel game, written from scratch, and it is not affiliated with or endorsed by
Mojang, Microsoft or Roblox. It shares a genre the way a platformer shares a genre: blocks, crafting and
a first-person view are the vocabulary, not the game. Quarrowen's own idea is that **the
world you join brings the game with it** — the client carries no content at all, so the same app is a
survival game with a story on one server and a fairground of short games on the next, depending only on
which world you are in.

## What does it cost?

Nothing. It is free to play, free to modify and free to share for anything noncommercial, under the
[PolyForm Noncommercial](../LICENSE) licence. That is deliberately **not** an OSI open source licence:
commercial use needs a separate one. Worth knowing before you build a business on it.

## What do I need to run it?

Any Mac - the download is a universal build, so Intel and Apple silicon both run it. It is signed and
notarized, so it opens by double-clicking with no security
detour.

There is a **Windows** build too, linked from the download page. It is unsigned, so Windows asks before
running it the first time, and it does not update itself yet - you download the new one when there is
one. Linux is not published, though the engine builds for it.

A server wants a Linux box with Docker — a spare mini PC or an old laptop is plenty for a family.

## Is it safe to join someone's server?

A server sends your game **data, never code**. There is no mod runtime in the client at all, nothing in
the protocol carries a script, and mods run on the machine hosting the world rather than yours.
[Security](security.md) says exactly what a server can and cannot do, including where the protections
end — it states the limits rather than softening them.

## Who can join my world?

Only the people you allow, and that is the default rather than a setting to find:

- **`ALLOWLIST` in the server's settings** names who may join, and travel between your own worlds
  carries the permission across, so nobody is bounced halfway through a portal.
- **Chat can be filtered**, and is not written to the server log.
- **Player creations** (painted skins, hats) can need approval before anyone else sees them.
- **No accounts, no email, no telemetry.** A player is a key on their own computer. Nothing is collected
  and nothing is sent anywhere except the server you chose to join.

## Can my friends and family play together?

Yes — that is what it is for. Run one server and everyone joins it from the menu. You can run several
worlds side by side — Firstlight, One Block and The Fairground is what the bundled setup runs — and walk
between them through portals or with `/server <name>`.

## Does it update itself?

Yes. The client checks when the menu opens and offers the new version; it never downloads from a game
server, only from the project's own address, and it checks a signature before installing. You can turn
the check off in Settings → Network.

A server and its players must run the same version — a mismatch is refused at the door with a message
saying so, rather than misbehaving quietly.

## Where are my worlds and settings kept?

`~/Library/Application Support/Quarrowen`. Settings → **Files** lists every folder with a button that
opens it, which is easier than finding that path by hand. Downloaded content is cleared out as it grows;
your worlds, creations and account key never are.

## Can I make my own blocks, creatures or games?

Yes, and that is the interesting part. A mod can add blocks, items, creatures, world generation, recipes,
machines, commands and UI, in **GDScript or JavaScript**, and everyone who joins your server downloads it
automatically. Start with [modding.md](modding.md); the full reference is
[api/index.html](api/index.html).

## What comes with it?

Four games and two add-ons, all in the download. **Firstlight** is the survival one: make it through the
night, dig, build, and come back out in the morning. **The Fairground** is a hub of short games with a
door to each - the floor is lava in one, a quiz where the wrong squares fall away in another - and every
one is worth playing on your own. **Creative** is a world and everything in it with nothing to survive.
**One Block** is a single block over the void that keeps becoming something else.

They exist partly to prove a point: every one of them is built on the same mod API anyone else can use,
with no private engine calls.

## Something is broken. What do I do?

Settings → **Files** → Logs, and look at the most recent one. For a server, `docker compose logs -f`. Then
open an issue with what you were doing and what the log said — a bug report from a real session is worth
more than any amount of testing.
