#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

# (C) 2016-2017 Maximilian Wende <dasisdormax@mailbox.org>
#
# This file is licensed under the Apache License 2.0. For more information,
# see the LICENSE file or visit: http://www.apache.org/licenses/LICENSE-2.0




Core.Setup::registerCommands () {
	simpleCommand "Core.Setup::beginSetup" setup
	simpleCommand "Core.Setup::printConfig" print-config
	simpleCommand "Core.Setup::listAddons" addons list-addons
	oneArgCommand "Core.Setup::enableAddon" enable-addon
	oneArgCommand "Core.Setup::disableAddon" disable-addon
	simpleCommand "Core.Setup::installAutomation" install-automation setup-automation
}




################################ CONFIG HANDLING ################################

requireConfig () {
	Core.Setup::validateConfig || error <<-EOF
		No valid configuration found!

		Create a new configuration using **$THIS_COMMAND setup**.
	EOF
}


requireAdmin () {
	requireConfig || return
	[[ $USER == $ADMIN ]] || error <<-EOF
		The user **$ADMIN** controls the base installation exclusively
		and is the only one who can perform actions on it!
	EOF
}


Core.Setup::loadConfig () {
	if ! .conf "$APP/cfg/defaults.conf"; then
		# Try migrating from older MSM versions
		.conf "cfg/app-$APP.conf" || return;
		[[ -O $USER_DIR ]] && Core.Setup::writeConfig && mv "$USER_DIR/cfg/app-$APP.conf"{,.old}
	fi
	Core.Setup::validateConfig
}


# load msm configuration file of the given user
Core.Setup::loadConfigOf () {
	USER_DIR="$(eval echo ~$1)/msm.d" Core.Setup::loadConfig
}


# Check the current configuration variables for correctness and plausibility
Core.Setup::validateConfig () {
	# Require admin variable
	[[ $ADMIN ]] || error <<< "variable \$ADMIN is not defined!" || return

	# Check base installation directory
	[[ $INSTALL_DIR                       ]] || error <<-EOF || return
			variable \$INSTALL_DIR is not defined!
		EOF

	[[ -r $INSTALL_DIR && -x $INSTALL_DIR ]] || error <<-EOF || return
			The base installation directory **$INSTALL_DIR**
			is not accessible!
		EOF

	INSTANCE_DIR="$INSTALL_DIR" Core.Instance::isBaseInstallation \
											 || error <<-EOF || return
			The directory **$INSTALL_DIR** is not a
			valid base installation for $APP!
		EOF
}


Core.Setup::writeConfig () {
	if Core.Setup::validateConfig; then
		if mkdir -p "$CFG_DIR" && Core.Setup::printConfig > "$CFG"; then
			[[ $USER != $ADMIN ]] || make-readable "$CFG"
		else
			fatal <<-EOF
				Error writing the configuration to **$CFG**!
				You may lack the necessary permissions to access the file!
			EOF
		fi
	else
		error <<< "Invalid configuration!"
	fi
}


Core.Setup::printConfig () {
	cat <<-EOF
		#! /bin/bash
		# This is a configuration file for Multi Server Manager with APP=$APP

		__ADMIN__=$ADMIN
		INSTALL_DIR="$INSTALL_DIR"
		DEFAULT_INSTANCE="$DEFAULT_INSTANCE"
		MSM_ADDONS="$MSM_ADDONS"
	EOF

	try App::printAdditionalConfig
	true
}




################################ ADDON MANAGEMENT ################################

# Lists all addons available (bundled and user-provided), marking which are enabled
Core.Setup::listAddons () {
	requireConfig || return
	log <<< ""
	info <<< "Available addons:"
	local dir name
	for dir in "$THIS_DIR"/addons/*/ "$USER_DIR"/addons/*/; do
		[[ -r "$dir/addon.info" ]] || continue
		name="$(basename "$dir")"
		if list-contains "$MSM_ADDONS" $name; then
			out <<< "    [x] $name"
		else
			out <<< "    [ ] $name"
		fi
	done
	out <<< ""
	out <<< "Enable/disable an addon using **$THIS_COMMAND enable-addon <name>** / **disable-addon <name>**."
}


Core.Setup::enableAddon () {
	requireAdmin || return
	[[ $1 ]] || return
	::moduleDir "$1" >/dev/null || error <<< "Addon **$1** was not found!" || return
	list-contains "$MSM_ADDONS" $1 && info <<< "Addon **$1** is already enabled." && return
	MSM_ADDONS="$MSM_ADDONS $1"
	Core.Setup::writeConfig && success <<< "Enabled addon **$1**. It will take effect on the next command."
}


Core.Setup::disableAddon () {
	requireAdmin || return
	[[ $1 ]] || return
	list-contains "$MSM_ADDONS" $1 || { info <<< "Addon **$1** is already disabled."; return; }
	MSM_ADDONS="$(list-diff "$MSM_ADDONS" $1)"
	Core.Setup::writeConfig && success <<< "Disabled addon **$1**."
}




############################### BOOT-TIME AUTOMATION ##############################

# Sets up both pieces of unattended operation in one go: a systemd unit that
# starts all instances on boot, and a crontab entry for the daily auto-update.
# Each step is independently idempotent and asks its own confirmation.
Core.Setup::installAutomation () {
	requireConfig || return
	Core.Setup::installSystemdService
	Core.Setup::installCronJob
}


# Generates (with real, resolved paths - no placeholders) and installs a
# systemd unit that runs "start-all"/"stop-all" on boot/shutdown, so every
# instance survives a reboot without any manual systemd setup. Idempotent -
# safe to re-run any time (e.g. after moving the checkout).
Core.Setup::installSystemdService () {
	requireConfig || return

	command -v systemctl >/dev/null || {
		info <<< "systemd (systemctl) was not found on this system - skipping boot auto-start setup."
		return
	}

	local SERVICE_NAME="$APP-multiserver"
	local UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"

	local tmp="$(mktemp)"
	cat > "$tmp" <<-EOF
		[Unit]
		Description=$APP_LONG Multi Server Manager - start all instances
		After=network-online.target
		Wants=network-online.target

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		User=$USER
		WorkingDirectory=$HOME
		ExecStart=$THIS_DIR/msm start-all
		ExecStop=$THIS_DIR/msm stop-all
		TimeoutStartSec=600
		TimeoutStopSec=60

		[Install]
		WantedBy=multi-user.target
	EOF

	out <<-EOF

		This will install a systemd unit at **$UNIT_FILE** that runs
		**$THIS_COMMAND start-all** on every boot and **$THIS_COMMAND stop-all** on
		shutdown, so all your instances come back automatically after a reboot.
		Requires sudo (daemon-reload + enable --now).
	EOF

	promptY "Install and enable this now?" || {
		rm -f "$tmp"
		info <<< "Skipped. Run **$THIS_COMMAND install-service** any time to set this up later."
		return
	}

	if sudo cp "$tmp" "$UNIT_FILE" && sudo systemctl daemon-reload \
			&& sudo systemctl enable --now "$SERVICE_NAME"
	then
		rm -f "$tmp"
		success <<< "Installed and enabled **$SERVICE_NAME** - instances will now start automatically on boot."
	else
		rm -f "$tmp"
		error <<-EOF
			Failed to install/enable the systemd service (check that your user can sudo).
			You can also install it manually - see **contrib/systemd/** in the
			cs2-multiserver checkout.
		EOF
	fi
}


# Adds a crontab entry (real, resolved script path - no placeholders) that
# updates the game + plugin pins and restarts every instance daily at 6 AM.
# Idempotent - won't add a duplicate entry if one already references the script.
Core.Setup::installCronJob () {
	requireConfig || return

	command -v crontab >/dev/null || {
		info <<< "crontab was not found on this system - skipping scheduled update setup."
		return
	}

	local SCRIPT="$THIS_DIR/contrib/cron/daily-update.sh"
	[[ -x $SCRIPT ]] || chmod +x "$SCRIPT" 2>/dev/null
	local LOGFILE="$USER_DIR/$APP/log/daily-update.log"
	mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null

	if crontab -l 2>/dev/null | grep -qF "$SCRIPT"; then
		info <<< "A cron entry for **$SCRIPT** already exists - leaving your crontab untouched."
		return
	fi

	local CRON_LINE="0 6 * * * $SCRIPT >> $LOGFILE 2>&1"

	out <<-EOF

		This will add the following line to your crontab, so $APP_SHORT (and any newer
		Metamod/CounterStrikeSharp/SwiftlyS2 builds) gets updated automatically every day
		at 6 AM, restarting all instances afterwards:

		    $CRON_LINE

	EOF

	promptY "Install this cron job now?" || {
		info <<< "Skipped. Run **$THIS_COMMAND install-cron** any time to set this up later."
		return
	}

	if ( crontab -l 2>/dev/null; echo "$CRON_LINE" ) | crontab -; then
		success <<< "Cron job installed - $APP_SHORT will auto-update and restart all instances daily at 6 AM."
	else
		error <<< "Failed to install the cron job. You can add it manually - see **contrib/cron/daily-update.sh**."
	fi
}




################################# INITIAL SETUP #################################

Core.Setup::beginSetup () {
	out <<< ""

	# Check, if config exists already
	[[ -e "$CFG" ]] && {
		info <<-EOF
			The config file **$CFG** already exists!
			If you want to start over, delete that file and run this command again.
		EOF
		return
	}

	out <<-EOF
		-------------------------------------------------------------------------------
		                 CS2 Multi-Mode Server Manager - Initial Setup
		-------------------------------------------------------------------------------

		It seems like this is the first time you use this script on this machine.
		Before advancing, be aware of a few things:

		>>  The configuration files will be saved in the directory:
		        **$CFG_DIR**

		    Make sure to backup any important data in that location.

	EOF

	promptY || return

	# Create config directory
	mkdir -p "$CFG_DIR" && [[ -w "$CFG_DIR" ]] || {
		fatal <<< "No permission to create or write the directory **$CFG_DIR**!"
		return
	}

	ADMIN=$USER
	Core.Setup::setupAsAdmin

	# Succeeds, if we have a valid config at the end
	Core.Setup::loadConfig
}




############################### ADMIN INSTALLATION ##############################

# TODO: make this function smaller
Core.Setup::setupAsAdmin () {

	log <<-EOF

		Basic Setup
		===========

		This assistant will install all remaining dependencies for your
		$APP server and create a basic configuration.  Please follow the
		instructions below.
	EOF

	######### Install App Downloader/Updater

	App::installUpdater || return

	######### Create base installation

	INSTANCE=
	INSTALL_DIR="$USER_DIR/$APP/base"
	until Core.BaseInstallation::isExisting; do
		bold <<-EOF

			Now, please select the **base installation directory**.  This is the
			directory the server will be downloaded to, make sure that there is
			plenty of free space on the disk.

		EOF

		read -r -p "Game Server Installation Directory (default: $USER_DIR/$APP/base) " INSTALL_DIR

		INSTALL_DIR=${INSTALL_DIR:-"$USER_DIR/$APP/base"}
		INSTALL_DIR="$(eval echo "$INSTALL_DIR")"   # expand tilde and stuff
		INSTALL_DIR="$(readlink -m "$INSTALL_DIR")" # get absolute directory

		Core.BaseInstallation::create
	done

	# Final Steps
	Core.Instance::select
	App::finalizeInstance
	Core.BaseInstallation::applyPermissions

	# Create Config and make it readable
	mkdir -p -m o-rwx "$TMPDIR" "$LOGDIR" "$INSTCFGDIR"
	# Create the initial instance configuration files
	cp -rn "$APP_DIR"/cfg/* "$INSTCFGDIR" 2>/dev/null

	MSM_ADDONS="$(try App::defaultAddons)"
	Core.Setup::writeConfig && {
		log <<< ""
		success <<-EOF
			Basic Setup Complete!

			Use **$THIS_COMMAND @name create** to create a new server instance out of
			your base installation.  Each instance can be configured independently and
			multiple instances can run simultaneously.
		EOF
		[[ $MSM_ADDONS ]] && info <<-EOF
			The following addons were enabled by default: **$MSM_ADDONS**
			(this installs Metamod:Source, CounterStrikeSharp and SwiftlyS2 on every
			instance's first start). Manage addons using **$THIS_COMMAND addons**.
		EOF

		out <<-EOF

			The actual $APP_SHORT game files (several GB) still need to be downloaded via
			SteamCMD. This can take a while - if you are on a flaky SSH connection,
			consider running it inside **tmux** so it survives a disconnect
			(tmux new -s install), then **$THIS_COMMAND install** in there.

		EOF
		if promptY "Install the $APP_SHORT game files now?"; then
			Core.BaseInstallation::requestUpdate
		else
			info <<< "You can install the game files later using **$THIS_COMMAND install**."
		fi

		Core.Setup::installAutomation
	}
}
