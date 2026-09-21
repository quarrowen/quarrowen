# Art kept out of the way

Source material that is **not loaded by anything**. Nothing here is on a mod's path; it is here so it
is not lost, and so it can be put back when there is something to put it back into.

## models/

The 43 glTF models from the games deleted on 21 September 2026, filed under the mod they came from.

**They are the only assets in this repository that no script can rebuild.** Everything else the games
used is generated and always was:

| | rebuilt by |
|---|---|
| block and item textures | `tools/generate_textures.gd` |
| sounds | `tools/generate_sounds.py` |
| music | `tools/generate_music.py` |
| structures | `tools/generate_structures.py`, `tools/generate_hearthhold.py` |
| simple box models (cables, pylons) | `tools/box_model.py` |

So this folder is the irreplaceable remainder: creatures (cow, pig, sheep, chicken, wolf, spider,
skeleton, slime, the colossus, the night stalker), the settler, beds, and the industry machines.

Worth knowing when they are wanted again: the engine draws a block or entity with **no model and no
texture** as a magenta checker, and that is enough to build and test against - the Proving Ground has
a rideable raft with no model at all. Art is what makes a thing *look* like something; it is not what
makes it work.
