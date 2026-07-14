#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

# Default list of plugins. If you think some should be added or removed, tell me
SM_BASE_PLUGINS="admin-flatfile adminhelp adminmenu antiflood basebans basechat basecommands basecomm basetriggers basevotes clientprefs playercommands"

SourcemodHelper::initVars () {
	# Weak defaults - can be overridden per-instance/preset in server.conf
	# SM_METAMOD: install Metamod:Source (base requirement for SourceMod and CSS)
	# SM_SOURCEMOD: install SourceMod (off by default - CounterStrikeSharp is the
	#               go-to plugin loader for CS2 now, enable this only for SM plugins)
	# SM_COUNTERSTRIKESHARP: install CounterStrikeSharp
	# SM_SWIFTLYS2: install SwiftlyS2, alongside Metamod/CounterStrikeSharp
	__SM_METAMOD__=1
	__SM_SOURCEMOD__=0
	__SM_COUNTERSTRIKESHARP__=1
	__SM_SWIFTLYS2__=1

	SM_HOME="$USER_DIR/$APP/addons/sourcemod-helper"
	SM_CONFIG_DIR="$SM_HOME/configs"
	SM_CSS_CONFIG_DIR="$SM_CONFIG_DIR/counterstrikesharp"
	SM_TMP_DIR="$SM_HOME/tmp"
	SM_TARGET_DIR="$INSTANCE_DIR/game/csgo"
	SM_FILECACHE_DIR="$SM_HOME/filecache"
	mkdir -p "$SM_TMP_DIR"
	mkdir -p "$SM_FILECACHE_DIR"
	SM_TMP_DIR="$(mktemp -d -p "$SM_TMP_DIR")"
	SM_TMP_CONFIG_DIR="$SM_TMP_DIR/addons/sourcemod/configs"
	SM_TMP_PLUGIN_DIR="$SM_TMP_DIR/addons/sourcemod/plugins"
	SM_TMP_EXTENSION_DIR="$SM_TMP_DIR/addons/sourcemod/extensions"
	SM_TMP_CSS_CONFIG_DIR="$SM_TMP_DIR/addons/counterstrikesharp/configs"
}
