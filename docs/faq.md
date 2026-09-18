# Questions

## Is this Minecraft?

No. It is an independent voxel game, written from scratch, and it is not affiliated with or endorsed by
Mojang, Microsoft or Roblox. It shares a genre the way a platformer shares a genre: blocks, crafting and
a first-person view are the vocabulary, not the game. Quarrowen's own idea is that **the server decides
the game** — the client carries no content at all, so the same app plays a survival world, an island
puzzle or a story, depending only on which server you join.

## What does it cost?

Nothing. It is free to play, free to modify and free to share for anything noncommercial, under the
[PolyForm Noncommercial](../LICENSE) licence. That is deliberately **not** an OSI open source licence:
commercial use needs a separate one. Worth knowing before you build a business on it.

## What do I need to run it?

A Mac with Apple silicon. It is signed and notarized, so it opens by double-clicking with no security
detour.

There is a **Windows** build too, linked from the download page. It is unsigned, so Windows asks before
running it the first time, and it does not update itself yet - you download the new one when there is
one. Linux is not published, though the engine builds for it.

A server wants a Linux box with Docker — a spare mini PC or an old laptop is plenty for a family.

## Is it safe for children?

It was built for children, and that has shaped it:

- **Only people you allow can join.** `ALLOWLIST` in the server's settings, and travel between your own
  worlds carries the permission across.
- **Chat can be filtered**, and is not written to the server log.
- **Player creations** (painted skins, hats) can require an adult's approval before anyone else sees them.
- **No accounts, no email, no telemetry.** A player is a key on their own computer. Nothing is collected
  and nothing is sent anywhere except the server you choose to join.
- Death messages and hints are written to be read by an eight-year-old at bedtime.

## Can my children play together?

Yes — that is what it is for. Run one server for the family and everyone joins it from the menu. You can
run several worlds side by side (a survival world, an island world, a story) and walk between them
through portals or with `/server <name>`.

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

## What is Hearthhold?

The story game that comes with it. A valley whose light went out: light the hearth, see the night out,
find the people who scattered into the hills and build them somewhere to live. It exists partly to prove
a point — everything it does is built on the same mod API anyone else can use.

## Something is broken. What do I do?

Settings → **Files** → Logs, and look at the most recent one. For a server, `docker compose logs -f`. Then
open an issue with what you were doing and what the log said — a bug report from a real session is worth
more than any amount of testing.
