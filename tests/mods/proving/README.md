# The Proving Ground

A game that exists to be tested, not played. It uses **every capability the engine has**, so that a
change to the engine breaks *this* and nothing else.

## Why it exists

Until 2026-09-21 the engine was tested through the games shipped with it - vanilla, hearthhold,
industry, arcana, guild, skyblock, oneblock. That meant every engine change dragged seven mods behind
it, and in one afternoon an argument order, a node tree, a write ordering and a music timer all had to
be chased through content that was going to be rewritten before 1.0 anyway.

It also meant coverage was accidental. A capability nothing happened to use was a capability nothing
tested, which is how 139 unbound JavaScript functions and 39 undocumented events went unnoticed.

## The rule

**If the engine can do it, this mod does it.** Adding a capability means adding it here in the same
commit. `tests/proving_test.gd` then asserts it worked.

## Shape

- `proving` (this mod, GDScript) - the game, and the GDScript half of the API.
- `proving_js` (addon, JavaScript) - the same ground covered through the JS bridge, so the two APIs
  cannot drift apart silently.
- `proving_lua` - once the Lua bridge exists.

Nothing here ships with a client or a server. It lives under `tests/` on purpose.
