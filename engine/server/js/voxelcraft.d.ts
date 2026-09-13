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
  }

  export interface ItemDef { display_name?: string; icon?: string; max_stack?: number; usable?: boolean; }

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

    on<E extends keyof Events>(event: E, handler: (event: Events[E]) => void, priority?: number): void;
    command(name: string, description: string, handler: (player: Player, args: string[]) => void, options?: { admin?: boolean }): void;
    after(seconds: number, fn: () => void): number;
    every(seconds: number, fn: () => void): number;
    cancel(taskId: number): void;
    storage: { get<T = unknown>(key: string, fallback?: T): T; set(key: string, value: unknown): void };
  }
}
