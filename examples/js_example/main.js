// A mod in JavaScript. The engine runs it in a sandbox: no file system, no network, no imports - just
// the `api` object it hands you, which is the same API GDScript mods get, in camelCase (registerItem,
// registerLoot, on...). That makes JavaScript the safer choice for a mod other people download.
//
// Try it: godot --path . -- --host=vanilla,js_example --dev   then break some blocks and type /coins
//
// Every function is in docs/api/index.html; mods/guild is a full game-sized JavaScript mod.

const REWARD_EVERY = 30; // blocks broken per coin

export function setup(api) {
  // Registering works as it does in GDScript; a name without a ":" belongs to this mod.
  // An icon is a file in this mod's folder, or "<mod>:<path>" to reuse one another mod already ships -
  // which is why this example needs no image files of its own.
  const coin = api.registerItem("coin", { display_name: "Shiny Coin", icon: "base:textures/coal.png" });

  // Events arrive as one object. Change a field to change what happens, or set cancelled to stop it.
  api.on("block_broken", (ev) => {
    // Per-player data is saved with the world and namespaced to this mod.
    const broken = (ev.player.getData("broken", 0) || 0) + 1;
    ev.player.setData("broken", broken);
    if (broken % REWARD_EVERY === 0) {
      ev.player.give(coin, 1);
      ev.player.sendMessage(`A coin for ${broken} blocks!`);
    }
  });

  // A command. The handler gets the player and the words after the command.
  api.command("coins", "How many blocks you have broken", (player) => {
    const broken = player.getData("broken", 0) || 0;
    player.sendMessage(`${broken} blocks broken - ${Math.floor(broken / REWARD_EVERY)} coins earned`);
  });

  // Timers: every() repeats, after() runs once, cancel() stops either.
  api.every(300, () => api.broadcast("Keep digging - every 30 blocks is a coin."));
}
