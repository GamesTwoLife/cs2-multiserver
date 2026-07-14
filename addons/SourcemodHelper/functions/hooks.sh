#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

::registerHook before~App::buildLaunchCommand SourcemodHelper::initVars
::registerHook after~App::buildLaunchCommand SourcemodHelper::updateInstance

# Also deploy plugins right when an instance is created (or cloned), not just
# on its first `start` - so a freshly created instance already has
# Metamod/CounterStrikeSharp/etc in place without needing a start first.
::registerHook after~Core.Instance::afterCreate SourcemodHelper::deployAtCreate

SourcemodHelper::deployAtCreate () {
	SourcemodHelper::initVars
	SourcemodHelper::updateInstance
}


SourcemodHelper::registerCommands () {
	simpleCommand "SourcemodHelper::fixExecStackCommand" fix-exec-stack
}


# On-demand version of the executable-stack sweep that normally runs as part
# of every `start`/`restart` - lets you re-apply it without a full server
# restart (e.g. right after dropping in a new plugin and using Metamod's own
# `meta load`, or just to double check after installing something by hand).
SourcemodHelper::fixExecStackCommand () {
	requireRunnableInstance || return
	command -v patchelf >/dev/null || error <<< "**patchelf** is not installed - run: sudo apt install patchelf" || return

	SourcemodHelper::initVars
	rmdir "$SM_TMP_DIR" 2>/dev/null # initVars creates a tmp dir we don't need here
	local dir="$SM_TARGET_DIR/addons"
	[[ -d $dir ]] || { info <<< "No addons directory found yet at **$dir**."; return; }

	info <<< "Clearing the executable-stack flag on every .so under **$dir** ..."
	SourcemodHelper::fixExecStack "$dir"
	success <<< "Done. If the server is already running, restart it (or use Metamod's **meta load**) for the change to take effect."
}

SourcemodHelper::updateInstance () {
	(( SM_METAMOD || SM_SWIFTLYS2 )) || {
		rmdir "$SM_TMP_DIR" 2>/dev/null
		return
	}
	warning <<-EOF
		The Sourcemod helper plugin is in alpha stage! This will overwrite
		your modifications in your instance's plugin loader files on every
		launch! You can update configuration for all managed instances by
		modifying the files in **$SM_CONFIG_DIR**
	EOF
	(
		cd "$SM_TMP_DIR"
		if (( SM_METAMOD )); then
			SourcemodHelper::loadPackage metamod || return
			SourcemodHelper::patchGameInfo metamod || return
		fi

		if (( SM_SOURCEMOD )); then
			catwarn <<< "SM_SOURCEMOD is enabled, but AlliedModders has not shipped a stable SourceMod build for CS2 (Source 2) yet - it will be installed, but will very likely NOT load. Track https://github.com/alliedmodders/sourcemod/issues/1958 for official support."
			SourcemodHelper::loadPackage sourcemod || return
		fi
		if (( SM_COUNTERSTRIKESHARP )); then
			(( SM_METAMOD )) || catwarn <<< "SM_COUNTERSTRIKESHARP is enabled but SM_METAMOD is off - CounterStrikeSharp is a Metamod plugin and cannot load without it."
			SourcemodHelper::loadPackage counterstrikesharp || return
			SourcemodHelper::fixExecStack addons/counterstrikesharp || return
			SourcemodHelper::updateCssConfig || return
		fi
		if (( SM_SWIFTLYS2 )); then
			SourcemodHelper::loadPackage swiftlys2 || return
			SourcemodHelper::fixExecStack addons/swiftlys2 || return
			SourcemodHelper::patchGameInfo swiftlys2 || return
		fi
		for package in $SM_PACKAGES; do
			SourcemodHelper::loadPackage $package || return
		done
		if (( SM_SOURCEMOD )); then
			SourcemodHelper::updateConfig || return
			SourcemodHelper::updatePlugins || return
		fi
	) || return

	# Copy addon files to instance's game directory
	cp -r "$SM_TMP_DIR"/* "$SM_TARGET_DIR"

	# Also sweep the instance's ENTIRE addons/ dir (not just what this addon
	# manages) for the executable-stack issue - covers third-party Metamod
	# plugins installed by hand (e.g. MultiAddonManager), which can hit the
	# exact same "cannot enable executable stack" failure on this system.
	SourcemodHelper::fixExecStack "$SM_TARGET_DIR/addons"

	# Move to last_state directory for easier debugging
	rm -rf "$SM_HOME/last_state"
	mv "$SM_TMP_DIR" "$SM_HOME/last_state"
}


# CS2 overwrites gameinfo.gi on every game update, wiping any search-path edit.
# Re-apply it on every start so plugin loaders keep working without manual
# intervention. New entries go right after the last already-patched
# "Game csgo/addons/..." line (or after Game_LowViolence for the first one),
# so call order here decides search-path order.
SourcemodHelper::patchGameInfo () {
	local searchpath="$1" gi="$SM_TARGET_DIR/gameinfo.gi"
	[[ -f $gi ]] || return 0
	grep -qF "csgo/addons/$searchpath" "$gi" && return 0

	local anchor
	anchor=$(grep -n 'Game[[:space:]]\+csgo/addons/' "$gi" | tail -1 | cut -d: -f1)
	[[ $anchor ]] || anchor=$(grep -n 'Game_LowViolence' "$gi" | head -1 | cut -d: -f1)
	[[ $anchor ]] || {
		catwarn <<< "Could not find where to patch gameinfo.gi for csgo/addons/$searchpath - please add 'Game csgo/addons/$searchpath' to the SearchPaths section manually."
		return 0
	}

	echo "Patching gameinfo.gi to load $searchpath ..."
	local tmp="$gi.msm-tmp"
	awk -v n="$anchor" -v entry="$searchpath" '
		{ print }
		NR==n { printf "\t\t\tGame\tcsgo/addons/%s\n", entry }
	' "$gi" > "$tmp" && mv "$tmp" "$gi"
}


# Clears the legacy GNU_STACK executable-stack flag that trips up Metamod
# plugin loading on newer kernels (see README - "cannot enable executable
# stack"). Called both on the packages we manage and as a full sweep over the
# instance's addons/ dir, so hand-installed third-party plugins get it too.
# No-op without patchelf installed.
SourcemodHelper::fixExecStack () {
	command -v patchelf >/dev/null || return 0
	local f
	while IFS= read -r -d '' f; do
		patchelf --clear-execstack "$f" 2>/dev/null
	done < <(find "$1" -name '*.so' -print0 2>/dev/null)
}


SourcemodHelper::updateCssConfig () {
	echo "Updating CounterStrikeSharp configuration ..."
	mkdir -p "$SM_CSS_CONFIG_DIR"

	# Seed persistent configs from CounterStrikeSharp's bundled examples on first run
	local example
	for example in "$SM_TMP_CSS_CONFIG_DIR"/*.example.json; do
		[[ -e $example ]] || continue
		local name="$(basename "$example")"
		cp -n "$example" "$SM_CSS_CONFIG_DIR/${name%.example.json}.json"
	done

	# The *.example.json templates have done their job (seeding above) - don't
	# deploy them into the instance, they'd just clutter the real configs dir
	rm -f "$SM_TMP_CSS_CONFIG_DIR"/*.example.json

	# Copy persisted configs to instance directory
	cp -r "$SM_CSS_CONFIG_DIR"/* "$SM_TMP_CSS_CONFIG_DIR"
}

SourcemodHelper::updateConfig () {
	# Initialize config dir
	echo "Updating sourcemod configuration ..."
	mkdir -p "$SM_CONFIG_DIR"
	cp -n "$SM_TMP_CONFIG_DIR/admins_simple.ini" "$SM_CONFIG_DIR"
	cp -n "$SM_TMP_CONFIG_DIR/databases.cfg" "$SM_CONFIG_DIR"
	
	# Copy configs to instance directory
	cp -r "$SM_CONFIG_DIR"/* "$SM_TMP_CONFIG_DIR"
}

SourcemodHelper::updatePlugins () {
	echo "Updating sourcemod plugins ..."

	# Disable all plugins first
	mkdir -p "$SM_TMP_PLUGIN_DIR/disabled"
	mv "$SM_TMP_PLUGIN_DIR"/*.smx "$SM_TMP_PLUGIN_DIR/disabled"

	# Re-enable the plugins that the user wants
	local plugin
	for plugin in $SM_PLUGINS; do
		mv "$SM_TMP_PLUGIN_DIR/disabled/$plugin.smx" "$SM_TMP_PLUGIN_DIR"
	done
}
