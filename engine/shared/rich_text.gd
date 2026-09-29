extends RefCounted
## Makes server-supplied text safe to put in a RichTextLabel with `bbcode_enabled`.
##
## **The problem.** Guide pages, tutorial steps and objective text are written by whichever mod the
## server is running, and the client draws them as BBCode. A server could therefore put `[img]` into a
## guide page and have the client load a resource out of its own build, or `[url]` to dress plain text
## up as a link, or `[color]` to make one sentence look like another part of the interface. None of that
## runs code - `meta_clicked` on the guide screen only ever calls `show_page`, never `OS.shell_open` -
## so this is a spoofing surface rather than an execution one. It is still not the client's to hand over.
##
## **Escaping everything was the wrong fix**, and was tried first: guide pages use `[b]` 66 times and
## `[i]` 16 times across the bundled mods, deliberately, and stripping those would turn the Survival
## Guide into a wall of flat text to close a hole nobody had opened. So the formatting tags a mod
## actually writes are allowed through and everything else is neutralised.
##
## `[lb]` is BBCode's own escape for a left bracket, so a neutralised tag is *shown* rather than
## swallowed: a mod that writes `[img]` sees `[img]` on the page and can tell what happened.
## (2026-09-29)

## What a mod may use. Deliberately short: this is a guidebook, not a document format. Adding to it
## means deciding that a server may control that part of how its text is drawn.
const ALLOWED := ["b", "/b", "i", "/i", "u", "/u"]


## Neutralises every BBCode tag except `ALLOWED`. Safe to call on text that contains none.
static func safe(text: String) -> String:
	if not text.contains("["):
		return text
	var out := text.replace("[", "[lb]")
	for tag: String in ALLOWED:
		out = out.replace("[lb]%s]" % tag, "[%s]" % tag)
	return out
