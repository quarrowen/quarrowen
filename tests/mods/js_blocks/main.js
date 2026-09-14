// Exercises the JavaScript bindings for containers, block ticks, fuel, processing and stations.
export function setup(api) {
api.registerContainer("crate", {
  title: "Crate",
  groups: [{ name: "items", count: 4 }, { name: "fuel", count: 1, accepts: "fuel" }],
  progress: [{ name: "fill", label: "Fill", color: "#80ff80" }],
});
api.registerBlock("crate", { textures: "base:textures/planks.png", container: "crate" });
api.registerBlock("workbench", { textures: "base:textures/planks.png", station: "workbench" });
api.registerRecipe({ "base:planks": 1 }, "base:stick", 8, { station: "workbench", needs: ["polish"] });
api.registerStation("workbench", { workshop: { radius: 2, upgrades: [{ block: "base:glass", grants: { features: ["polish"] } }] } });
api.setFuel("base:gravel", 7);
api.registerProcess("pressing", "base:gravel", "base:cobblestone", 2, 4);

// Every change a player makes marks the crate with a coal (so the test can see the handler ran).
api.on("container_changed", ({ container, position }) => {
  if (container.type !== "js_blocks:crate") return;
  const items = api.containerItems(position);
  const filled = items.filter((s) => s.item > 0).length;
  api.setContainerProgress(position, "fill", filled / 5);
  api.setContainerState(position, { filled, press: api.getProcess("pressing", api.item("base:gravel")) });
});

api.registerBlockTick("crate", ({ position, ticks, reason }) => {
  const left = api.addToContainer(position, api.item("base:coal"), ticks, {}, "items");
  api.setContainerState(position, { ...api.containerState(position), reason, left, fuel: api.getFuel(api.item("base:gravel")) });
}, { interval: 5 });
}
