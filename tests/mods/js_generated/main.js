// Every call here reaches mod_api.gd through the generated table (engine/server/js/bindings.json).
// None of these has a hand-written entry in prelude.js, so if the generated half breaks, this mod
// fails to load rather than the breakage waiting to be found in somebody's game.
//
// Picked to cover each argument kind the table has to describe: strings and dictionaries, a player
// reference, a number with a default left off, and a callback.
export function setup(api) {
  api.registerLedger("coins", { display_name: "Coins", min: 0 });
  api.registerObjective("errand", { display_name: "An Errand", steps: [{ text: "Go there" }] });
  api.registerShop("stall", {
    display_name: "The Stall",
    offers: [{ item: "base:torch", count: 2, price: 5, ledger: "coins", stock: 1 }],
  });
  api.registerCharacter("wend", {
    display_name: "Wend",
    lines: { start: { text: "Morning.", options: [{ text: "Shop", sells: "stall" }] } },
  });

  // A callback crossing the generated path: the prelude turns it into an id, the bridge turns the id
  // back into a Callable.
  api.registerCommand("jsledger", "What a player has", (player) => {
    player.sendMessage(`coins: ${api.balanceOf(player, "coins")}`);
  });

  api.on("player_join", ({ player }) => {
    api.addBalance(player, "coins", 12);          // player + str + float
    api.giveObjective(player, "errand");          // player + str
    // A trailing argument left off must keep the GDScript default, not become an empty dictionary.
    api.talkTo(player, "wend");
  });
}
