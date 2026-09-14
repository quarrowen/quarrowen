// Throws on purpose: /jscrash calls a missing function; /jslog logs at every level.
export function setup(api) {
  api.command("jscrash", "Throw an error", () => {
    const broken = null;
    broken.explode(); // line 5: the error the test expects
  });
  api.command("jslog", "Log at every level", () => {
    console.debug("js detail");
    console.log("hello from js", { answer: 42 });
    console.warn("js running low");
  });
}
