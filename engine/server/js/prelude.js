// VoxelCraft JavaScript mod API. Evaluated before a mod's main module.
//
// A mod is an ES module exporting `setup(api)`:
//
//   export function setup(api) {
//     const ruby = api.registerBlock("ruby_ore", { textures: "textures/ruby.png", light: 5 });
//     api.on("block_broken", (ev) => { if (ev.block === ruby) ev.player.showTitle("Shiny!"); });
//   }
//
// Every call crosses into the engine as JSON, so values are plain data: positions are {x, y, z},
// players are Player objects, block/item ids are numbers. Types: engine/server/js/voxelcraft.d.ts.
"use strict";

(() => {
  const callbacks = new Map();
  let nextCallback = 1;

  const register = (fn) => {
    if (typeof fn !== "function") throw new TypeError("expected a function");
    const id = nextCallback++;
    callbacks.set(id, fn);
    return id;
  };

  const host = (method, ...args) => {
    const reply = JSON.parse(__host_call(method, JSON.stringify(args, toHost)));
    if (reply !== null && typeof reply === "object" && "__error" in reply) {
      throw new Error(`${method}: ${reply.__error}`);
    }
    return revive(reply?.value ?? null);
  };

  const toHost = (_key, value) => (value instanceof Player ? { __player: value.id } : value);

  const revive = (value) => {
    if (Array.isArray(value)) return value.map(revive);
    if (value !== null && typeof value === "object") {
      if ("__player" in value) return new Player(value.__player, value.name);
      const out = {};
      for (const [k, v] of Object.entries(value)) out[k] = revive(v);
      return out;
    }
    return value;
  };

  class Player {
    constructor(id, name) {
      this.id = id;
      this.name = name;
    }
    get position() { return host("player.position", this.id); }
    get eyePosition() { return host("player.eyePosition", this.id); }
    get yaw() { return host("player.yaw", this.id); }
    get lookDirection() { return host("player.lookDirection", this.id); }
    get online() { return host("player.online", this.id); }
    give(item, count = 1) { return host("player.give", this.id, item, count); }
    take(item, count = 1) { return host("player.take", this.id, item, count); }
    countOf(item) { return host("player.countOf", this.id, item); }
    teleport(position) { host("player.teleport", this.id, position); }
    sendMessage(text) { host("player.sendMessage", this.id, String(text)); }
    showTitle(text, subtitle = "", seconds = 3) { host("player.showTitle", this.id, String(text), String(subtitle), seconds); }
    showUi(id, spec) { host("player.showUi", this.id, id, spec); }
    hideUi(id) { host("player.hideUi", this.id, id); }
    isCreative() { return host("player.isCreative", this.id); }
    isAdmin() { return host("player.isAdmin", this.id); }
    setCreative(enabled) { host("player.setCreative", this.id, !!enabled); }
    setHotbar(items) { host("player.setHotbar", this.id, items); }
    /** Persistent per-player data, namespaced to this mod. */
    getData(key, fallback = null) { return host("player.getData", this.id, key, fallback); }
    setData(key, value) { host("player.setData", this.id, key, value); }
    kick(reason) { host("player.kick", this.id, reason); }
  }

  const api = {
    Player,
    info: (...parts) => host("info", parts.map(String).join(" ")),
    // Content
    registerBlock: (name, def) => host("registerBlock", name, def),
    registerItem: (name, def) => host("registerItem", name, def),
    registerRecipe: (inputs, output, count = 1) => host("registerRecipe", inputs, output, count),
    block: (name) => host("block", name),
    item: (name) => host("item", name),
    itemName: (id) => host("itemName", id),
    itemDisplayName: (id) => host("itemDisplayName", id),
    blockName: (id) => host("blockName", id),
    isSolid: (id) => host("isSolid", id),
    getDrops: (id) => host("getDrops", id),
    addOrePass: (def) => host("addOrePass", def),
    // World
    getBlock: (pos) => host("getBlock", pos),
    getLoadedBlock: (pos) => host("getLoadedBlock", pos),
    setBlock: (pos, id, { keepData = false, state = 0 } = {}) => host("setBlock", pos, id, keepData, state),
    fill: (from, to, id) => host("fill", from, to, id),
    getBlockState: (pos) => host("getBlockState", pos),
    getBlockData: (pos) => host("getBlockData", pos),
    setBlockData: (pos, data) => host("setBlockData", pos, data),
    clearBlockData: (pos) => host("clearBlockData", pos),
    findBlockData: (block = -1) => host("findBlockData", block),
    surfaceY: (x, z) => host("surfaceY", x, z),
    seesSky: (pos) => host("seesSky", pos),
    setPhysics: (values) => host("setPhysics", values),
    setWorldTime: (timeOfDay, dayLength = -1) => host("setWorldTime", timeOfDay, dayLength),
    timeOfDay: () => host("timeOfDay"),
    daylight: () => host("daylight"),
    facingFromYaw: (yaw) => host("facingFromYaw", yaw),
    // Players & server
    players: () => host("players"),
    findPlayer: (name) => host("findPlayer", name),
    broadcast: (text) => host("broadcast", String(text)),
    setServerInfo: (values) => host("setServerInfo", values),
    showCrafting: (player) => host("showCrafting", player),
    // Events, commands, timers
    on: (event, handler, priority = 0) => host("on", event, register(handler), priority),
    command: (name, description, handler, { admin = false } = {}) =>
      host("command", name, description, register(handler), admin ? "admin" : ""),
    after: (seconds, fn) => host("after", seconds, register(fn)),
    every: (seconds, fn) => host("every", seconds, register(fn)),
    cancel: (taskId) => host("cancel", taskId),
    // Persistent per-mod storage, saved with the world
    storage: {
      get: (key, fallback = null) => host("storageGet", key, fallback),
      set: (key, value) => host("storageSet", key, value),
    },
  };

  globalThis.console = {
    log: (...parts) => api.info(...parts),
    warn: (...parts) => api.info("warning:", ...parts),
    error: (...parts) => api.info("error:", ...parts),
  };

  globalThis.__setup = (_json) => {
    const exports = globalThis.__exports ?? {};
    const setup = exports.setup ?? exports.default;
    if (typeof setup !== "function") throw new Error("a JavaScript mod must export function setup(api)");
    setup(api);
    return "null";
  };

  // Engine -> script: invokes a registered callback. Events are plain objects; the fields handlers
  // may change (cancelled, drops) are sent back.
  globalThis.__dispatch = (json) => {
    const { id, args } = JSON.parse(json);
    const fn = callbacks.get(id);
    if (!fn) return JSON.stringify({ value: null });
    const revived = revive(args);
    const result = fn(...revived);
    const first = revived[0];
    const event = first !== null && typeof first === "object" && !(first instanceof Player) && !Array.isArray(first)
      ? { cancelled: first.cancelled, drops: first.drops }
      : null;
    return JSON.stringify({ value: result ?? null, event }, toHost);
  };
})();
