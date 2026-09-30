#!/usr/bin/env python3
"""Merges the landing page template with the values a release computes.

    tools/build_landing.py site/landing values.json out/index.html

**Why the page is split in two.** It used to be a 370-line heredoc inside
tools/make_release.sh, so every word on the site lived inside a shell script: a change of
copy was a change to the release tooling, a diff of a sentence was unreadable, and nobody
who was not already editing the build could edit the page. The prose is the part people
give feedback on and the numbers are the part a release knows, so they are now separate
files that meet here. (2026-09-30)

The template is ordinary HTML with `{{name}}` in the handful of places a value goes. No
loops, no conditions, no expressions - anything that needs deciding is decided in the
release script, which is where the artifacts are. A templating language would invite the
logic back in one placeholder at a time, which is how the heredoc happened.

**Every placeholder in the template must be supplied, and every value must be used.** Both
directions are errors rather than warnings: a missing one would publish the literal text
"{{mac_url}}" as a download link, and an unused one means a value the release worked out
and the page silently dropped - which is how a page ends up quietly not saying the thing
somebody added.
"""

import json
import pathlib
import re
import sys

PLACEHOLDER = re.compile(r"\{\{([a-z_][a-z_0-9]*)\}\}")


def build(template_dir: pathlib.Path, values: dict) -> str:
    html = (template_dir / "index.html").read_text()
    css = (template_dir / "style.css").read_text()
    # The stylesheet is inlined rather than linked: the page is one file that has to work
    # from a folder, an archive or a download, and a second request for 4 KB of CSS buys
    # nothing. It lives apart in the repository so it can be edited as a stylesheet.
    values = dict(values, style="<style>\n" + css.rstrip("\n") + "\n</style>")

    wanted = set(PLACEHOLDER.findall(html))
    missing = sorted(wanted - values.keys())
    if missing:
        raise SystemExit("landing template wants values nothing supplied: " + ", ".join(missing))
    unused = sorted(values.keys() - wanted)
    if unused:
        raise SystemExit("values supplied that the template never uses: " + ", ".join(unused))

    return PLACEHOLDER.sub(lambda m: str(values[m.group(1)]), html)


def main(argv: list) -> int:
    if len(argv) != 4:
        raise SystemExit(__doc__.strip().splitlines()[2].strip())
    template_dir, values_path, out_path = (pathlib.Path(a) for a in argv[1:])
    values = json.loads(values_path.read_text())
    if not isinstance(values, dict):
        raise SystemExit("%s is not a JSON object" % values_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(build(template_dir, values))
    print("[landing] wrote %s (%d bytes)" % (out_path, out_path.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
