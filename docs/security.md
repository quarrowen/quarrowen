# Security

Quarrowen's whole pitch is that the server decides the game: you download one app, join somebody's
server, and their blocks, creatures and rules arrive. The obvious question follows immediately.

**If a server sends me its game, is it sending me code?**

No. A server sends data and never code. Your client has no mod runtime in it at all — there is no
GDScript engine reachable from the network, no JavaScript engine on the client side, and no message in
the protocol that carries a `.gd`, a `.js`, a `.zip` or a mod of any kind. Mods run on the machine
hosting the world. Your copy draws what it is told about.

This page says what that does and does not protect you from. The limits are at the bottom and they are
not softened; a security page that only lists reassurances is an advertisement.

## What a server can send you, and what happens to it

| What arrives | Treated as | Bounded by |
|---|---|---|
| Blocks, items, creatures, recipes, effects, sounds | Dictionaries of numbers and strings | Every field is range-checked and clamped; anything invalid disconnects you rather than being guessed at |
| Textures, models, audio | Files, stored under their own SHA-256 | 16 MB each, 256 MB total, 4096 files; only `png`, `ogg`, `wav`, `glb` and `json` may be published at all, and only images, audio and binary models are ever decoded |
| Terrain | Compressed voxel data | Hard size ceiling per chunk; malformed chunks are dropped |
| Interface panels | Seven widget types: label, button, progress, image, box, spacer | Six levels deep, 64 children, 400 characters, sizes and colours clamped |
| Guide and tutorial text | Text with bold and italic | Every other formatting tag is neutralised and shown rather than obeyed |
| Chat | Plain text | 300 characters, drawn as a plain label — not rich text, so nothing in a message can format or link |
| Other players' skins and models | Content-addressed files | 64×64 PNG, or a model under 512 KB and 4,000 triangles; **your client re-checks all of it rather than trusting the server's word** |

A server cannot choose a filename on your disk. Downloaded content is stored under the hash of its own
contents, verified before it is written, so one server cannot poison another's files or overwrite
anything you own.

## What a server cannot do

- **Run code on your machine.** There is no path for it. This is structural, not a policy.
- **Give you an update.** Updates come only from this project's own address, must be signed by a key
  built into your copy, must download from an allowlisted host, and must match a checksum inside the
  signed manifest. A server that tells your client it is out of date can only make the button appear —
  the check that follows is your client's own, and the server has no say in where it looks.
- **Install a mod on your computer.** Mods come from a signed index, over allowlisted hosts, with
  checksums, and only when you click install.
- **Open a link, run a program, read your files, or write anywhere except its own cache.**
- **Change your settings, or make you type a command.**

## What it cannot protect you from

Four things. None of them is theoretical hand-waving; they are the actual edges.

**The first connection to a new address is trust-on-first-use.** The very first time you connect
somewhere, your client has nothing to compare against, so it trusts whoever answers and remembers their
certificate. Every connection after that is cryptographically pinned — an impostor cannot complete the
handshake. But somebody controlling your network at that first moment could impersonate the server from
then on. This is the same bargain SSH makes.

Related, and worth knowing before you meet it: if a server's identity later changes, you are told, and
offered a button to trust the new one. That exists because servers do get rebuilt. **Only press it if
you know why the identity changed.**

**Your client parses files written by the server.** Images, models, audio and compressed terrain are
decoded by the game engine's own native code. Sizes, dimensions and triangle counts are capped, which
limits what a malformed file can attempt, but a bug in an image or model decoder would be reachable by
any server you connect to. This is the strongest reason to prefer servers you have some reason to trust,
and to keep the game updated.

**A server can ask to send you to another server.** That is how linked worlds work — walking through a
portal between someone's two worlds. If the destination is one your computer has connected to before, it
happens seamlessly. **If it is somewhere new, you are asked first**, because arriving somewhere new means
a fresh trust-on-first-use connection that carries your name and your public key with it.

**Servers can tell it is you.** Your identity is a keypair on your own computer, and the public half goes
to every server you join. There are no accounts and nothing is collected centrally, but two servers
comparing notes could tell that the same person visited both. That is the cost of having an identity at
all without having an account.

Beyond those: a server can put panels, titles, sounds and effects on your screen as often as it likes.
There is no rate limit. It is an annoyance rather than a danger, and leaving ends it.

## If you host a server

The trust runs the other way, and it is much stronger. **A mod you install runs with the full privileges
of the game on your machine** — it is ordinary code in your own process, not sandboxed. Install mods the
way you would install any other program.

The exception is JavaScript mods, which run in a sandbox with no file access, no network, no `require`,
a memory ceiling and a deadline that interrupts an infinite loop. That is tested, not asserted:
`tests/js_sandbox_test.gd` checks each of those directly.

Your players cannot make you run anything. What arrives from a player is their name, their key, their
appearance and anything they are wearing — all of it size-limited and validated before it is stored.

## Where things are kept

Everything is on your own machine: worlds, settings, your identity key, your creations, and caches of
what servers have sent you. Nothing is sent anywhere except the server you chose to join. There is no
account, no email address, no telemetry and no analytics. The caches have size budgets and are pruned
oldest-first; the things you would miss are never pruned.

## Reporting something

If you find a security problem, please report it privately rather than opening a public issue — see
[CONTRIBUTING.md](https://github.com/quarrowen/quarrowen/blob/master/CONTRIBUTING.md).

## How this page is kept honest

Every claim here was checked against the code on 29 September 2026, and the checks that can be automated
are in the test suite rather than in somebody's memory: the JavaScript sandbox, certificate pinning
against a forged certificate, the update manifest's signature and host rules, and the guard that stops a
server sending you to your own machine.
