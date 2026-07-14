#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

# (C) 2016-2017 Maximilian Wende <dasisdormax@mailbox.org>
#
# This file is licensed under the Apache License 2.0. For more information,
# see the LICENSE file or visit: http://www.apache.org/licenses/LICENSE-2.0




App::isRunnableInstance () [[ -x $INSTANCE_DIR/$SERVER_EXEC ]]


# addons enabled by default for freshly set up installations (see Core.Setup::setupAsAdmin)
App::defaultAddons () { echo "SourcemodHelper SteamAPIHelper AddonTemplate"; }


# Auto-assigns a PORT that doesn't collide with any existing instance's PORT,
# by scanning every other instance's actual resolved port and picking
# max+100. GOTV's TV_PORT is always PORT+5 (see cs2/app/cfg/gotv.conf), so a
# gap of 100 leaves plenty of room for it too. Appends a strong PORT=
# override at the end of the instance's freshly created server.conf, which
# wins over whatever default/copied value came before it in the file.
App::assignInstancePort () {
	local conf="$INSTCFGDIR/server.conf"
	[[ -f $conf ]] || return 0

	local maxport=0
	local inst p
	for inst in $(Core.Instance::listInstances); do
		[[ $inst == $INSTANCE ]] && continue
		p="$(
			INSTANCE=$inst
			Core.Instance::select
			unset PORT
			.file "$INSTCFGDIR/server.conf" 2>/dev/null
			applyDefaults
			echo "$PORT"
		)"
		[[ $p =~ ^[0-9]+$ ]] && (( p > maxport )) && maxport=$p
	done

	# Deliberately not `local` - App::allowFirewallPorts (called separately,
	# since a clone reassigns the port after this runs) reads it back.
	ASSIGNED_PORT=27015
	(( maxport > 0 )) && ASSIGNED_PORT=$(( maxport + 100 ))

	{
		echo ""
		echo "# Auto-assigned by cs2-server create/clone to avoid colliding with other instances"
		echo "PORT=\"$ASSIGNED_PORT\""
	} >> "$conf"

	info <<< "Assigned **PORT=$ASSIGNED_PORT** to this instance (GOTV follows automatically at PORT+5)."
}


# Opens the instance's game port and GOTV port (game port + 5) in ufw, with
# both TCP and UDP allowed (`ufw allow <port>` without a protocol suffix
# covers both). No-op if ufw isn't installed. Asks for confirmation first,
# since this changes firewall rules.
App::allowFirewallPorts () {
	[[ $ASSIGNED_PORT ]] || return 0
	command -v ufw >/dev/null || return 0

	local tvport=$(( ASSIGNED_PORT + 5 ))

	out <<-EOF

		This instance uses port **$ASSIGNED_PORT** (game) and **$tvport** (GOTV),
		both TCP+UDP.
	EOF
	promptY "Allow these ports through ufw now?" || {
		info <<< "Skipped. Open them later with: sudo ufw allow $ASSIGNED_PORT && sudo ufw allow $tvport"
		return
	}

	if sudo ufw allow "$ASSIGNED_PORT" comment "cs2-multiserver @$INSTANCE" \
			&& sudo ufw allow "$tvport" comment "cs2-multiserver @$INSTANCE (GOTV)"
	then
		success <<< "Opened ports **$ASSIGNED_PORT** and **$tvport** in ufw."
	else
		error <<< "Failed to update ufw rules - check manually with 'sudo ufw status'."
	fi
}


# files/directories to copy fully 
App::instanceCopiedFiles () { cat <<-EOF ; }
	game/csgo/addons
	game/csgo/cfg
	game/csgo/models
	game/csgo/sound
	game/csgo/gameinfo.gi
EOF


# directories, in which the user can put own files in addition to the provided ones
App::instanceMixedDirs () { cat <<-EOF ; }
	game/csgo/maps
	game/csgo/maps/cfg
	game/csgo/maps/soundcache
	game/csgo/logs
	game/csgo/resource/overviews
	game/bin/linuxsteamrt64
EOF


# files/directories which are not shared between the base installation and the instances
App::instanceIgnoredFiles () { cat <<-EOF ; }
	game/csgo/addons
	game/csgo/replays
EOF


App::finalizeInstance () (
	[[ "$INSTANCE_DIR" != "$INSTALL_DIR" ]] && {
		# Make sure each instance has its own up-to-date cs2 binary
		rm "$INSTANCE_DIR/$SERVER_EXEC"
		cp "$INSTALL_DIR/$SERVER_EXEC" "$INSTANCE_DIR/$SERVER_EXEC"
	}
	# copy presets from app to user config directory
	mkdir -p "$CFG_DIR/presets"
	cp -n "$APP_DIR"/presets/* "$CFG_DIR/presets"

	# Defensive: also run here (not just after `update`), in case an instance is
	# created/launched against a base installation that predates this fix.
	App::fixMissingEngineLibs
)


App::applyInstancePermissions () {
	# Remove read privileges for files that may contain sensitive data
	# (such as passwords, IP addresses, etc)
	
	chmod -R o-r "$INSTANCE_DIR/msm.d/cfg"
	chmod o-r "$INSTANCE_DIR/game/csgo/cfg/autoexec.cfg"
	chmod o-r "$INSTANCE_DIR/game/csgo/cfg/server.cfg"
	true
} 2>/dev/null


App::varsToPass () { cat <<-EOF ; }
	APP
	MODE
	TEAM_T
	TEAM_CT
	IP
	PORT
	TV_PORT
	PASS
	USE_RCON
	RCON_PASS
	SLOTS
	ADMIN_SLOTS
	TAGS
	TITLE
EOF
