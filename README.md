# CS2 Multi Server Manager (MSM)

A bash toolkit for setting up and running Counter-Strike 2 dedicated servers, with support
for multiple independent instances sharing one game install.

This is a maintained fork of [dasisdormax/cs2-multiserver](https://github.com/dasisdormax/cs2-multiserver)
by Maximilian Wende. The original project laid out the instance/addon architecture this
fork builds on; see [Fork notes](#fork-notes) below for what's changed.

*cs2-multiserver* is built for LAN and small hosting setups: it manages several server
instances on one or more machines, and instances share base game files (maps, textures,
binaries) instead of each needing its own multi-gigabyte copy.


## Features

- SteamCMD-based install and update of the CS2 dedicated server
- Multiple instances per machine, each with its own config, port, and gamemode, sharing one
  base install
- Metamod:Source, CounterStrikeSharp, and SwiftlyS2 installed and kept up to date
  automatically through the `SourcemodHelper` addon
- Automatic port assignment on `create`/`clone` so instances never collide, including the
  GOTV port
- One-command boot auto-start (systemd) and scheduled updates (cron)
- Gamemode presets (competitive, casual, wingman, deathmatch, surf, tournament, ...), plus
  support for your own per-instance rulesets
- tmux-based process supervision with automatic restart on crash


## Getting started

### Prerequisites

Runs under `bash` on Linux (or WSL2 on Windows). SteamCMD is a 32-bit binary, so you'll need
the 32-bit compatibility libraries for your distro - see the
[SteamCMD wiki page](https://developer.valvesoftware.com/wiki/SteamCMD#Linux). Budget at
least 60 GB of disk space for the base install.

On Ubuntu:

```bash
sudo apt install lib32gcc-s1 lib32stdc++6 jq unzip inotify-tools patchelf
```

`patchelf` isn't strictly required, but without it some Metamod plugins (including
CounterStrikeSharp) won't load on recent kernels - see [Known issues](#known-issues).

You'll also need a Steam account that owns CS2, since installing and running the dedicated
server requires an active login. Have your Steam Guard code ready during setup.

### Install

```bash
git clone https://github.com/GamesTwoLife/cs2-multiserver.git
cd cs2-multiserver
ln -s "$(pwd)/msm" /usr/local/bin/cs2-server   # optional, for a shorter command
cs2-server setup
```

`setup` walks you through the Steam login, base install location, and offers to install the
game files and set up boot/cron automation right away. Everything can also be run
individually later with `cs2-server install`, `cs2-server install-automation`, etc.


## Instances

Individual servers are called instances. They share most files with the base install but
keep their own config. `@name` selects which instance a command applies to; `@` with no name
targets the base install directly (fine if you only run one server).

```bash
cs2-server @test01 create
```

`create` picks a `PORT` that doesn't collide with any existing instance (highest configured
port + 100; GOTV's port is always `PORT + 5`, so the gap covers it too), deploys
Metamod/CounterStrikeSharp/etc immediately, and - if `ufw` is present - offers to open the
new ports.

To spin up a copy of an existing instance (same preset, password, everything) with a fresh
port instead of starting from the template:

```bash
cs2-server @test01 clone test02
```

### Managing several instances at once

```bash
cs2-server list-instances
cs2-server start-all
cs2-server stop-all
cs2-server restart-all
```

### Day to day

```bash
cs2-server @test01 start
cs2-server @test01 stop
cs2-server @test01 restart
cs2-server @test01 status
cs2-server @test01 console      # attach to the game console; CTRL-D detaches, CTRL-K kills
cs2-server @test01 exec <cmd>   # run a single console command without attaching
```

The server runs inside tmux and gets automatically relaunched if it crashes or exits for any
reason other than an explicit `cs2-server stop` - including if someone types `quit` directly
in the console.


## Configuration

Per-instance settings live in `~/msm.d/cs2/cfg/inst-<name>/server.conf`. `PORT` is assigned
automatically on `create`/`clone`; edit the file directly if you want a specific value.
Options can also be overridden per-invocation:

```bash
MAP='de_nuke' cs2-server @test01 start
```

### Gamemode presets

Each instance loads a preset via `PRESET="name"`, which pulls in
`~/msm.d/cs2/cfg/presets/<name>.conf`. Bundled presets (`competitive`, `casual`,
`deathmatch`, `headshots`, `wingman`, `surf`, `tournament`) get copied there the first time
an instance is created, and are never overwritten by later updates.

A preset just sets `GAMETYPE`/`GAMEMODE` (see `cs2/app/gamemodes.txt`) plus any extra cvars:

```sh
# casual.conf
__GAMETYPE__=0
__GAMEMODE__=0
GAMEMODE_CUSTOM=(
	"mp_warmuptime 0"
	"mp_warmup_pausetimer 0"
)
```

Presets in `~/msm.d/cs2/cfg/presets/` are shared across every instance that references them
by name. If you want a ruleset for one instance only, copy the preset under a new name
(`cp casual.conf casual-test01.conf`) rather than editing the shared file.


## Plugins

New setups enable the bundled `SourcemodHelper` addon, which installs and keeps up to date:

| Plugin | Version | Notes |
|---|---|---|
| Metamod:Source | 2.0.0-git1406 | must stay on the `2.x` branch - the `1.1x` branch (used by CS:GO, TF2, etc.) has no CS2 support and fails silently |
| CounterStrikeSharp | v1.0.371 | Linux "with-runtime" build, bundles its own .NET runtime |
| SwiftlyS2 | v1.4.3 | on by default alongside Metamod/CounterStrikeSharp |
| SourceMod | 1.12.0-git7245 | opt-in, off by default - see below |

`cs2-server update` checks GitHub for newer builds after every game update and asks before
touching anything. You can also edit the URL/checksum in `addons/SourcemodHelper/packages/*.sh`
by hand.

Toggle components per instance in `server.conf`:

```sh
SM_METAMOD=1             # base requirement, on by default
SM_COUNTERSTRIKESHARP=1  # needs Metamod
SM_SOURCEMOD=1           # off by default; "tournament" preset turns it on for WarMod
SM_SWIFTLYS2=1           # on by default
```

SourceMod does not currently work on CS2 - AlliedModders hasn't shipped a Source 2 build
([alliedmodders/sourcemod#1958](https://github.com/alliedmodders/sourcemod/issues/1958)).
Setting `SM_SOURCEMOD=1` still deploys it, but it won't load. Use CounterStrikeSharp instead
unless you specifically need a SourceMod-only plugin.

SwiftlyS2 doesn't require Metamod. To run it standalone on an instance:

```sh
SM_METAMOD=0
SM_COUNTERSTRIKESHARP=0
SM_SWIFTLYS2=1
```

Plugins are deployed both when an instance is created/cloned and on every start, so a fresh
instance already has them in place. CounterStrikeSharp plugins go in
`game/csgo/addons/counterstrikesharp/plugins/`; their configs persist in
`~/msm.d/cs2/addons/sourcemod-helper/configs/counterstrikesharp/` across restarts.

Check `meta list` and `css_plugins list` in the console to confirm what actually loaded.

Existing installs can enable this after the fact:

```bash
cs2-server addons
cs2-server enable-addon SourcemodHelper
```


## Known issues

### `libv8*.so: cannot open shared object file`

Some CS2 Linux builds ship the V8 (`cs_script`) shared libraries only in
`game/bin/linuxsteamrt64/`, while `libserver.so` needs them next to itself. This tool
symlinks them into place automatically after every `update`/`install` and when an instance
is created - no manual steps needed.

### `cannot enable executable stack as shared object requires: Invalid argument`

Recent kernels/glibc (seen on Ubuntu 26.04) refuse to load shared objects that request an
executable stack, which several Metamod plugins' native libraries still request out of habit
(CounterStrikeSharp, SwiftlyS2, and third-party plugins like MultiAddonManager have all hit
this). The fix is `patchelf --clear-execstack` on the affected `.so` files -
`SourcemodHelper` applies it automatically, both to the plugins it manages and, on every
start, as a sweep over the instance's entire `addons/` directory, so hand-installed plugins
get it too. Requires `patchelf` to be installed; see the
[background on this issue](https://github.com/roflmuffin/CounterStrikeSharp/issues/1024).

Run `cs2-server @instance fix-exec-stack` to reapply the fix without a full restart.

### Stray `Unknown command` warnings from Valve's own gamemode configs

`gamemode_competitive.cfg`/`gamemode_casual.cfg` (shipped inside the game's own `pak01.vpk`,
not generated by this tool) reference a couple of cvars that no longer exist on CS2
(`mp_weapons_glow_on_ground`, `sv_gameinstructor_enable`). Harmless, and not something this
tool can fix without shadowing Valve's file and re-verifying it on every update.


## Automation

```bash
cs2-server install-automation
```

Sets up both boot auto-start and scheduled updates in one step, each with its own
confirmation prompt. Safe to run again later, e.g. after moving the checkout.

- **Boot auto-start**: installs a systemd unit at `/etc/systemd/system/<app>-multiserver.service`
  that runs `start-all`/`stop-all` on boot/shutdown (needs `sudo`). A static template with
  placeholder paths is also available at
  [`contrib/systemd/cs2-multiserver.service.example`](contrib/systemd/cs2-multiserver.service.example)
  if you'd rather set it up by hand.
- **Scheduled updates**: adds a crontab entry that runs
  [`contrib/cron/daily-update.sh`](contrib/cron/daily-update.sh) at 6 AM daily. It updates
  the game and plugin pins, then restarts every instance so the new files actually get
  picked up. Since there's no terminal attached under cron, the plugin-update confirmation
  prompt defaults to yes - remove the `update` line from the script if you'd rather bump
  plugin versions manually.

`cs2-server setup` offers to run this at the end of a fresh install too.


## Fork notes

This fork picks up where upstream left off after its CS:GO-to-CS2 migration, which the
original author had marked untested. Changes here:

- Fixed the instance target path used by the plugin loader, which pointed at a directory
  that never existed under CS2's `game/csgo` layout
- Added automatic `gameinfo.gi` patching, since CS2 wipes the Metamod search-path entry on
  every game update
- Added CounterStrikeSharp and SwiftlyS2 support, updated Metamod/SourceMod to current
  builds
- Fixed the `libv8*.so` and executable-stack issues that otherwise prevent the server (and
  several plugins) from starting on current Linux distributions
- Added automatic port assignment, instance cloning, `ufw` integration, and one-command
  boot/cron automation
- Removed a couple of CS2 cvars from the generated configs that turned out not to exist on
  the dedicated server build, despite being documented elsewhere

Bug reports and PRs welcome, same as upstream.


## License

Apache License 2.0, inherited from upstream. The original CS:GO-era code was based on
[csgo-server-launcher](https://github.com/crazy-max/csgo-server-launcher) (LGPLv3); see the
upstream repository for the exact history of that license transition.
