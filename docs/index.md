# Quarrowen

A voxel game engine in Godot with a Rust extension, built so that **the engine provides capabilities
and mods provide content**. If a feature names a particular block, item or story it belongs in a mod;
if it lets *any* mod do that kind of thing it belongs in the engine.

That line is why this reference exists and why it is the shape it is. The mod API is over 260
functions and none of them require reaching into engine internals, so a mod written against it keeps
working: the loudest complaint about modding in this genre is that every release rewrites the
internals and every mod must be rewritten with them. Here nothing forces that.

## The reference

[Mod API](api/mod-api.md)
:   Every function a mod can call. Start here.

[Engine internals](api/engine.md)
:   The registries and readers behind the API, grouped by the question they answer rather than by folder.

[How do I…](api/how-do-i.md)
:   The short path to a task when you know what you want and not what it is called.

All three are **generated from the engine's own sources**, so they cannot drift from the code — a
test fails when they are stale. Each entry carries its signature, the remarks its doc comment holds,
and a **See Also** derived from what the function actually calls, following through private helpers
because the useful link usually runs through one.

## Guides

- **[Writing a mod](modding.md)** — from an empty folder to something that loads, in GDScript or JavaScript.
- **[Loot tables](loot.md)** — weights, pools and how "how likely is this drop" is actually answered.
- **[Running a server](hosting.md)** — for a family, a classroom or the public.
- **[Distributing a build](distribution.md)** — packaging and release.

## A note on content

The engine ships with `base`, which owns **nouns** — blocks, liquids, biomes, flora and fauna, the
things that simply exist. Progression, recipes and survival are **rules**, and rules belong to a
game. The test of whether that line is holding is a blunt one: a creative game ships zero recipes and
everything still exists and works.

So if you are looking for where the furnace recipe lives, it is not in `base`, and that is deliberate.
