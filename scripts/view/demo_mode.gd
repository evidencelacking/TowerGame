class_name DemoMode
extends RefCounted
## Demo mode (#262): `python tools/play.py --demo`. A new tower with a huge balance, the top star
## rating and everything unlocked, for trying every tool. Demo towers never touch the save files.

const FUNDS := 100_000_000_000  ## Starting balance, through the ordinary starting-funds setting.
const STARS := 5

## Set by the UI tester, which cannot pass command-line arguments to itself.
static var forced: bool = false


## True when the game was started with --demo (after Godot's "--"), or the tester forced it.
static func active() -> bool:
	return forced or "--demo" in OS.get_cmdline_user_args()
