// Type declarations for VoxelCraft JavaScript mods. Reference from a mod for editor autocomplete:
//   /// <reference path="../../engine/server/js/voxelcraft.d.ts" />
//   /** @param {import("voxelcraft").Api} api */
//   export function setup(api) { ... }
// or author in TypeScript and compile to main.js.

declare module "voxelcraft" {
  export interface Vec3 { x: number; y: number; z: number; }

  export type BlockId = number;
  /** Block ids (1-65534) double as their items; other items start at 65536. */
  export type ItemId = number;

  export interface BlockDef {
    display_name?: string;
    /** One texture for all faces, or per-face paths relative to the mod folder. */
    textures?: string | { all?: string; side?: string; top?: string; bottom?: string } | string[];
    render?: "opaque" | "cutout" | "translucent" | "invisible" | "model";
    solid?: boolean;
    liquid?: boolean;
    breakable?: boolean;
    placeable?: boolean;
    /** Light emitted, 0-15. */
    light?: number;
    /** Right-click fires block_interact instead of placing. */
    interactive?: boolean;
    /** glTF (.glb) model path; the block renders as that model. */
    model?: string;
    orientation?: "none" | "horizontal";
    connect_group?: string;
    model_arm?: string;
    sway?: boolean;
    /** Item name dropped when broken, "" for nothing, or [[itemId, count], ...]. */
    drops?: string | [ItemId, number][];
    /** Sound names ("base:stone", or this mod's) for breaking, placing and walking on the block. */
    sounds?: { break?: string; place?: string; step?: string };
  }

  export interface ItemDef {
    display_name?: string; icon?: string; max_stack?: number; usable?: boolean;
    /** Damage when attacking while holding it (default 1). */
    attack_damage?: number;
  }

  export interface EntityDef {
    display_name?: string;
    kind?: "mob" | "projectile" | "object";
    /** glTF model; parts named leg_a/leg_b/arm_a/arm_b swing while walking. Faces -Z. */
    model?: string;
    /** Billboard texture when there is no model (projectiles). */
    sprite?: string;
    glow?: boolean;
    width?: number; height?: number; scale?: number;
    health?: number; speed?: number; gravity?: number; drag?: number; knockback_resistance?: number;
    ai?: "none" | "wander" | "passive" | "hostile";
    attack_damage?: number; attack_range?: number; attack_cooldown?: number; sight_range?: number;
    /** Projectile damage on hit. */
    damage?: number;
    lifetime?: number;
    /** [[item name, count, chance?], ...] dropped on death. */
    drops?: [string, number, number?][];
    sounds?: { hurt?: string; death?: string; ambient?: string; attack?: string };
    /** Saved with the world (otherwise despawns when no player is near). */
    persistent?: boolean;
  }

  export interface SpawnRule {
    entity: string; time?: "night" | "day" | "any"; on?: string[];
    max_nearby?: number; max_total?: number; chance?: number; min_distance?: number; max_distance?: number;
  }

  export interface Gameplay {
    item_drops?: "entity" | "inventory"; keep_inventory?: boolean; pvp?: boolean;
    fall_damage?: boolean; natural_regeneration?: boolean; mob_spawning?: boolean;
  }

  export class Entity {
    readonly id: number;
    readonly type: string;
    readonly kind: string;
    /** Dropped item stacks: the item and count. */
    readonly item: ItemId;
    readonly count: number;
    readonly alive: boolean;
    position: Vec3;
    velocity: Vec3;
    readonly health: number;
    readonly maxHealth: number;
    push(impulse: Vec3): void;
    damage(amount: number, attacker?: Player | Entity | null, cause?: string): boolean;
    heal(amount: number): void;
    remove(): void;
    setGoal(position: Vec3 | null): void;
    getData<T = unknown>(key: string, fallback?: T): T;
    setData(key: string, value: unknown): void;
  }

  export interface OrePassDef {
    ore: string; replace?: string; veins?: number; size?: number; min_y?: number; max_y?: number; chance?: number;
  }

  export type UiElement =
    | { type: "label"; text: string; size?: number; color?: string }
    | { type: "button"; text: string; action: string; disabled?: boolean }
    | { type: "progress"; value: number; max: number }
    | { type: "image"; asset: string; size?: number }
    | { type: "vbox" | "hbox"; children: UiElement[] }
    | { type: "spacer"; size?: number };

  export interface UiSpec {
    anchor?: "top_left" | "top_right" | "bottom_left" | "bottom_right" | "center" | "center_top" | "center_left" | "center_right";
    modal?: boolean;
    children: UiElement[];
  }

  export class Player {
    readonly id: number;
    readonly name: string;
    readonly position: Vec3;
    readonly eyePosition: Vec3;
    readonly yaw: number;
    readonly lookDirection: Vec3;
    readonly online: boolean;
    give(item: ItemId, count?: number): number;
    take(item: ItemId, count?: number): boolean;
    countOf(item: ItemId): number;
    teleport(position: Vec3): void;
    sendMessage(text: string): void;
    showTitle(text: string, subtitle?: string, seconds?: number): void;
    /** UI ids are namespaced to the mod automatically ("board" -> "guild:board"). */
    showUi(id: string, spec: UiSpec): void;
    hideUi(id: string): void;
    isCreative(): boolean;
    isAdmin(): boolean;
    setCreative(enabled: boolean): void;
    setHotbar(items: ItemId[]): void;
    getData<T = unknown>(key: string, fallback?: T): T;
    setData(key: string, value: unknown): void;
    kick(reason: string): void;
    readonly health: number;
    readonly maxHealth: number;
    readonly dead: boolean;
    setHealth(value: number): void;
    heal(amount: number): void;
    damage(amount: number, cause?: string, attacker?: Player | Entity | null): boolean;
    playSound(name: string, volume?: number, pitch?: number): void;
    drop(item: ItemId, count?: number): void;
    push(impulse: Vec3): void;
    setSpawnPoint(position: Vec3 | null): void;
  }

  export interface Events {
    player_join: { player: Player; first_time: boolean };
    player_leave: { player: Player };
    tick: { delta: number; tick: number };
    block_break: { player: Player; position: Vec3; block: BlockId; drops: [ItemId, number][]; cancelled: boolean };
    block_broken: { player: Player; position: Vec3; block: BlockId };
    block_place: { player: Player; position: Vec3; block: BlockId; cancelled: boolean };
    block_placed: { player: Player; position: Vec3; block: BlockId };
    block_interact: { player: Player; position: Vec3; block: BlockId };
    item_use: { player: Player; item: ItemId; has_target: boolean; position: Vec3; normal: Vec3; direction: Vec3 };
    item_crafted: { player: Player; item: ItemId; count: number };
    chat: { player: Player; text: string; cancelled: boolean };
    ui_action: { player: Player; ui_id: string; action: string };
    item_drop: { player: Player; item: ItemId; count: number; cancelled: boolean };
    item_pickup: { player: Player; entity: Entity; item: ItemId; count: number; cancelled: boolean };
    player_attack: { player: Player; target: Entity | Player; target_kind: "entity" | "player"; item: ItemId; damage: number; cancelled: boolean };
    player_damage: { player: Player; amount: number; cause: string; attacker: Player | Entity | null; cancelled: boolean };
    player_death: { player: Player; cause: string; attacker: Player | Entity | null; keep_inventory: boolean; message: string };
    player_respawn: { player: Player; position: Vec3 };
    entity_spawned: { entity: Entity };
    entity_removed: { entity: Entity };
    entity_damage: { entity: Entity; amount: number; cause: string; attacker: Player | Entity | null; cancelled: boolean };
    entity_death: { entity: Entity; cause: string; attacker: Player | Entity | null; drops: [ItemId, number][] };
    entity_interact: { player: Player; entity: Entity; item: ItemId };
    entity_natural_spawn: { type: string; position: Vec3; cancelled: boolean };
    projectile_hit: { entity: Entity; owner: Player | Entity | null; hit: "block" | "entity" | "player"; target: Player | Entity | null;
      position: Vec3; block: Vec3; damage: number; cancelled: boolean; keep: boolean };
  }

  export interface Api {
    info(...parts: unknown[]): void;
    registerBlock(name: string, def: BlockDef): BlockId;
    registerItem(name: string, def: ItemDef): ItemId;
    registerRecipe(inputs: Record<string, number>, output: string, count?: number): void;
    block(name: string): BlockId;
    item(name: string): ItemId;
    itemName(id: ItemId): string;
    itemDisplayName(id: ItemId): string;
    blockName(id: BlockId): string;
    isSolid(id: BlockId): boolean;
    getDrops(id: BlockId): [ItemId, number][];
    /** World generation hook for JavaScript mods (scripts cannot run on generation threads). */
    addOrePass(def: OrePassDef): void;

    getBlock(position: Vec3): BlockId;
    getLoadedBlock(position: Vec3): BlockId;
    setBlock(position: Vec3, id: BlockId, options?: { keepData?: boolean; state?: number }): void;
    fill(from: Vec3, to: Vec3, id: BlockId): void;
    getBlockState(position: Vec3): number;
    /** Returns a copy: call setBlockData to save changes. */
    getBlockData<T = Record<string, unknown>>(position: Vec3): T;
    setBlockData(position: Vec3, data: Record<string, unknown>): void;
    clearBlockData(position: Vec3): void;
    findBlockData(block?: BlockId): Vec3[];
    surfaceY(x: number, z: number): number;
    seesSky(position: Vec3): boolean;
    setPhysics(values: Record<string, number | boolean>): void;
    setWorldTime(timeOfDay: number, dayLength?: number): void;
    timeOfDay(): number;
    daylight(): number;
    facingFromYaw(yaw: number): number;

    players(): Player[];
    findPlayer(name: string): Player | null;
    broadcast(text: string): void;
    setServerInfo(values: { name?: string; description?: string; motd?: string }): void;
    showCrafting(player: Player): void;

    registerEntity(name: string, def: EntityDef): number;
    registerSound(name: string, files: string | string[], options?: { volume?: number; pitch?: number; pitch_variance?: number; range?: number }): number;
    playSound(name: string, position: Vec3, volume?: number, pitch?: number): void;
    spawnEntity(type: string, position: Vec3, options?: { yaw?: number; velocity?: Vec3; data?: Record<string, unknown> }): Entity | null;
    spawnProjectile(type: string, from: Vec3, velocity: Vec3, owner?: Player | Entity | null): Entity | null;
    dropItem(item: ItemId, count: number, position: Vec3): Entity | null;
    entities(center: Vec3, radius: number, type?: string): Entity[];
    addSpawnRule(rule: SpawnRule): void;
    setGameplay(values: Gameplay): void;
    getGameplay<K extends keyof Gameplay>(rule: K): Gameplay[K];

    on<E extends keyof Events>(event: E, handler: (event: Events[E]) => void, priority?: number): void;
    command(name: string, description: string, handler: (player: Player, args: string[]) => void, options?: { admin?: boolean }): void;
    after(seconds: number, fn: () => void): number;
    every(seconds: number, fn: () => void): number;
    cancel(taskId: number): void;
    storage: { get<T = unknown>(key: string, fallback?: T): T; set(key: string, value: unknown): void };
  }
}
