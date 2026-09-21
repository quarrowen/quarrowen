// The JavaScript half of the Proving Ground.
//
// Deliberately covers the same ground as the GDScript half rather than different ground: the point is
// that both languages can reach the same engine, and the only way that stays true is if something
// calls it in both. 139 of 262 functions were unreachable from here for weeks because nothing did.
//
// Most of what this calls has **no hand-written binding**. It goes through the table generated from
// mod_api.gd's own signatures (engine/server/js/bindings.json), which is exactly what should be
// exercised: a hand-written binding fails loudly, a generated one fails by being absent.
export function setup(api) {
  // Registration, through the generated half of the bridge.
  api.registerLedger("js_coins", { display_name: "JS Coins", min: 0 });
  api.registerObjective("js_errand", { display_name: "A JS Errand", steps: [{ text: "Do it" }] });
  api.registerCondition("js_chill", {
    display_name: "Chill",
    good: false,
    modifiers: [{ stat: "move_speed", amount: -0.2, op: "multiply" }],
  });
  api.registerField("js_puddle", {
    radius: 2.5,
    seconds: 6,
    effect: "engine:sparkle",
    tick: { seconds: 1, damage: 1, cause: "puddle" },
  });
  api.registerShop("js_stall", {
    display_name: "The JS Stall",
    offers: [{ item: "proving:token", count: 1, price: 2, ledger: "js_coins", stock: 2 }],
  });
  api.registerCharacter("js_keeper", {
    display_name: "The JS Keeper",
    lines: {
      start: {
        text: "Written in another language entirely.",
        options: [
          { text: "Shop", sells: "js_stall" },
          { text: "Work", gives: "js_errand" },
          { text: "Nothing", does: "shrug" },
        ],
      },
    },
  });
  api.registerOrder("js_wait", { display_name: "Wait here" });

  // Blocks and items, through hand-written bindings, so both halves of the bridge are covered.
  const slab = api.registerBlock("js_block", {
    display_name: "JS Block",
    hardness: 1,
  });
  api.registerItem("js_item", { display_name: "JS Item" });
  api.registerRecipe({ "proving:rock": 1 }, "proving_js:js_block", 1, { unlock: "known" });

  // Player and entity objects, and arguments of every kind the table has to describe: a player
  // reference, a position, a number left off, a dictionary, and a callback.
  api.registerCommand("jsprove", "Exercise the JavaScript bridge", (player) => {
    api.addBalance(player, "js_coins", 5);          // player + str + float
    api.giveObjective(player, "js_errand");          // player + str
    api.giveCondition(player, "js_chill", { seconds: 5 }); // target + str + dict
    api.placeField("js_puddle", player.position);    // str + vec3, options left off
    api.floatText("js", player.position, { color: "#88ddff" });
    api.setNameplate(player, { lines: ["via JavaScript"] });
    player.sendMessage(`js_coins: ${api.balanceOf(player, "js_coins")}, block ${slab}`);
  });

  api.on("character_choice", ({ player, character, choice }) => {
    if (character === "proving_js:js_keeper" && choice === "shrug") api.addBalance(player, "js_coins", 1);
  });

  // An event handler that writes to a container, which is what proved the JavaScript runtime could not
  // be re-entered. It stays here so that it cannot quietly stop being covered.
  api.on("container_changed", ({ container, position }) => {
    if (container.type !== "proving:crate") return;
    const items = api.containerItems(position);
    api.setContainerState(position, { ...api.containerState(position), js_seen: items.length });
  });
}
