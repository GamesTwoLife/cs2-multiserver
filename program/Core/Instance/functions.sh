#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

# (C) 2016-2017 Maximilian Wende <dasisdormax@mailbox.org>
#
# This file is licensed under the Apache License 2.0. For more information,
# see the LICENSE file or visit: http://www.apache.org/licenses/LICENSE-2.0




Core.Instance::registerCommands () {
	simpleCommand "Core.Instance::create" create create-instance
	simpleCommand "Core.Instance::listInstances" list-instances
	simpleCommand "Core.Instance::startAll" start-all
	simpleCommand "Core.Instance::stopAll" stop-all
	simpleCommand "Core.Instance::restartAll" restart-all
	oneArgCommand "Core.Instance::importFrom" import-from
	oneArgCommand "Core.Instance::cloneInstance" clone
}




################################ INSTANCE HELPERS ################################

requireRunnableInstance () {
	requireConfig || return
	Core.Instance::isRunnableInstance || error <<-EOF
		Cannot access or run **$INSTANCE_TEXT**!

		Make sure that a) the server is properly installed and b) that
		you have the necessary privileges for that instance's directory.
	EOF
}


# true, if an instance exists in directory $INSTANCE_DIR
Core.Instance::isInstance () [[
	$(cat "$INSTANCE_DIR/msm.d/app" 2>/dev/null) == $APP
]]


Core.Instance::isRunnableInstance () {
	Core.Instance::isInstance && [[ -w "$INSTANCE_DIR" ]] && App::isRunnableInstance
}


# true, if $INSTANCE_DIR is a base installation
Core.Instance::isBaseInstallation () {
	Core.Instance::isInstance && [[ -e $INSTANCE_DIR/msm.d/is-admin ]]
}


# true, if $INSTANCE_DIR can be used as directory for a new instance
Core.Instance::isValidDir () {
	[[ ! -e $INSTANCE_DIR ]] || [[ -d $INSTANCE_DIR && ! $(ls -A "$INSTANCE_DIR") ]]
}


# does all the necessary preparations to run and manage an instance that was
# created by a previous MSM version
Core.Instance::migrate () {
	local OLDINST_DIR="$USER_DIR/$APP/$PREV_SUFFIX"

	# moves an old instance to the new location
	if ! Core.Instance::isInstance; then
		if [[ $INSTANCE ]] && INSTANCE_DIR="$OLDINST_DIR" Core.Instance::isInstance; then
			mkdir -p "$(dirname "$INSTANCE_DIR")"
			mv "$INSTANCE_DIR" "$USER_DIR/$APP/backup-$(timestamp)-$INSTANCE" 2>/dev/null
			mv "$OLDINST_DIR" "$INSTANCE_DIR" || return
		else
			return
		fi
	fi

	# NOTE: because of the 'return' further up, we can assume this to be a valid
	# >     instance from now on
	# move logs to the new directory
	[[ -d $LOGDIR ]] || {
		mkdir -p -m o-rwx "$LOGDIR"
		mv "$USER_DIR/$APP/log/$PREV_SUFFIX/"* "$LOGDIR" 2>/dev/null
	}
	# copy configs to the new directory
	[[ -d $INSTCFGDIR ]] || {
		mkdir -p -m o-rwx "$INSTCFGDIR"
		cp -r "$CFG_DIR/$PREV_SUFFIX/"* "$INSTCFGDIR" 2>/dev/null
	}
	true
}


# update instance-related variables
Core.Instance::select () {
	if [[ $INSTANCE ]]; then
		PREV_SUFFIX="inst/$INSTANCE"
		INSTANCE_SUFFIX="inst-$INSTANCE"
		INSTANCE_DIR="$USER_DIR/$APP/$INSTANCE_SUFFIX"
		INSTANCE_TEXT="Instance @$INSTANCE"
	else
		INSTANCE_SUFFIX="base"
		INSTANCE_DIR="$INSTALL_DIR"
		INSTANCE_TEXT="Base Installation"
	fi
	# Other locations
	INSTCFGDIR="$CFG_DIR/$INSTANCE_SUFFIX"
	TMPDIR="$INSTANCE_DIR/msm.d/tmp"
	LOGDIR="$USER_DIR/$APP/log/$INSTANCE_SUFFIX"
	SOCKET="$TMPDIR/server.tmux-socket"
	Core.Instance::migrate
}


# Lists all instances (except the base installation) that the current user owns
# Also checks the instances and performs necessary migrations
Core.Instance::listInstances () (
	list=" "
	for file in "$USER_DIR/$APP/inst-"* "$HOME/$APP@"*; do
		[[ -e $file ]] || continue
		INSTANCE="${file##*[/@]}"
		INSTANCE="${INSTANCE#inst-}"
		list-contains "$list" $INSTANCE && continue
		Core.Instance::select
		Core.Instance::isInstance && {
			echo "$INSTANCE"
			list="$list$INSTANCE "
		}
	done
)


# Runs $1 (a Core.Server:: request function) against every instance the current
# user owns (not the base installation). Intended for boot-time automation
# (systemd) or after a scripted `cs2-server update` (cron). Each instance runs
# in its own subshell so one failure doesn't abort the rest.
Core.Instance::forEachInstance () {
	requireConfig || return
	local list="$(Core.Instance::listInstances)"
	[[ $list ]] || { info <<< "No instances found."; return; }
	local inst
	for inst in $list; do
		( INSTANCE=$inst; Core.Instance::select; "$1"; )
	done
}

Core.Instance::startAll ()   { Core.Instance::forEachInstance Core.Server::requestStart; }
Core.Instance::stopAll ()    { Core.Instance::forEachInstance Core.Server::requestStop; }
Core.Instance::restartAll () { Core.Instance::forEachInstance Core.Server::requestRestart; }




###################### SERVER INSTANCE MANAGEMENT FUNCTIONS ######################

# recursively symlinks all files from the base installation that do not exist yet in the instance
# TODO: instead of checking for a donotlink file, respect App::instanceIgnoredDirs
Core.Instance::symlinkFiles () {
	local IGNORE=" $(echo $(App::instanceIgnoredFiles)) msm.d "
	local pwd="$(pwd)/"
	local dir="${pwd#"$INSTANCE_DIR/"}"
	local BASE_DIR="$INSTALL_DIR/$dir"
	debug <<< "Processing directory **$dir**"

	# Loop through files in directory
	for file in $(ls -A "$BASE_DIR"); do
		# Skip files that are not readable for the current user
		[[ ! -r $BASE_DIR$file ]] && continue

		# Skip ignored files
		[[ $IGNORE =~ " $dir$file " ]] && log <<-EOF >&3 && continue
			  --- IGNORED $dir$file.
		EOF

		# Skip existing symlinks
		[[ -L $file ]] && continue

		# recurse through subdirectories
		[[ -d $file ]] && {
			( cd $file; Core.Instance::symlinkFiles; )
			continue
		}

		# Create symlink for files that do not exist yet in the target directory
		[[ ! -e $file ]] &&	ln -s "$BASE_DIR$file" "$file" && log <<-EOF >&3
			  + SYMLINKED $dir$file.
		EOF

	done
	out <<< "" >&3
}


Core.Instance::copyFiles () {
	local file
	for file in $(App::instanceCopiedFiles); do
		local dir="$(dirname "$file")"
		[[ $dir ]] && mkdir -p "$dir"
		[[ -e $INSTALL_DIR/$file ]] && cp -R "$INSTALL_DIR/$file" "$file"
	done
}


Core.Instance::makeDirectories () {
	local dir
	# Create mixed directories
	for dir in $(App::instanceMixedDirs); do
		mkdir -p "$dir"
	done
	# Create base for ignored dirs
	for dir in $(App::instanceIgnoredFiles); do
		local dir="$(dirname "$dir")"
		[[ $dir ]] && mkdir -p "$dir"
	done
}


Core.Instance::create () (

	log <<< ""
	requireConfig || return

	Core.Instance::isBaseInstallation && warning <<-EOF && return
			Directory **$INSTANCE_DIR** contains a base installation.
			Create a new instance using **$THIS_COMMAND @name create**.
		EOF

	Core.Instance::isInstance && info <<-EOF && return
			Directory **$INSTANCE_DIR** already contains a valid instance.
		EOF

	if ! Core.Instance::isValidDir; then
		warning <<-EOF
			The directory **$INSTANCE_DIR** is non-empty, creating an
			instance here may cause **LOSS OF DATA**!

			Please backup all important files before proceeding!
		EOF
		sleep 2
		promptN || return
	fi

	############ INSTANCE CREATION STARTS NOW ############
	info <<< "Creating an instance in directory **$INSTANCE_DIR** ..."

	mkdir -p "$INSTANCE_DIR" && [[ -w "$INSTANCE_DIR" ]] || {
		fatal <<< "No permission to create or write the directory **$INSTANCE_DIR**!"
		return
	}

	cd "$INSTANCE_DIR"
	rm -rf msm.d 2>/dev/null
	mkdir msm.d

	log <<< ""
	log <<< "Copying instance-specific files ..."
	Core.Instance::copyFiles

	log <<< "Creating additional directories ..."
	Core.Instance::makeDirectories

	log <<< "Linking remaining files to base installation ..."
	Core.Instance::symlinkFiles

	log <<< "Finishing instance creation ..."

	App::finalizeInstance
	App::applyInstancePermissions

	mkdir -p -m o-rwx "$TMPDIR" "$LOGDIR" "$INSTCFGDIR"
	# Create the initial instance configuration files
	cp -rn "$APP_DIR"/cfg/* "$INSTCFGDIR" 2>/dev/null
	# Save the APP of this instance directory
	echo $APP > "msm.d/app"

	# Auto-assign a port that doesn't collide with any existing instance
	# (GOTV's port follows automatically, it's always PORT+5 - see cs2/app/cfg/gotv.conf)
	try App::assignInstancePort

	# Skipped when called from ::cloneInstance, which reassigns the port
	# afterwards and opens the firewall for the final one itself
	[[ $MSM_SKIP_FIREWALL ]] || try App::allowFirewallPorts

	log <<< "Installing plugins (Metamod/CounterStrikeSharp/...) if configured ..."
	::hookable Core.Instance::afterCreate

	success <<-EOF
		Instance created successfully!

		Now, edit your instance's configuration files, located
		in **$INSTCFGDIR**, to set IP, port,
		passwords and other game settings of your instance.
	EOF
)


# Creates a new instance ($1) as a copy of the currently selected one, with its
# own config (server.conf/gotv.conf overlaid from the source) and a freshly
# assigned, non-colliding port.
Core.Instance::cloneInstance () (
	[[ $1 ]] || error <<< "Usage: **$THIS_COMMAND @source clone <newname>**" || return
	requireConfig || return
	Core.Instance::isInstance || error <<-EOF || return
		**$INSTANCE_TEXT** is not a valid instance - nothing to clone.
	EOF

	local SRC_INSTANCE="$INSTANCE"
	local SRC_CFGDIR="$INSTCFGDIR"
	local NEWNAME="$1"

	[[ $NEWNAME != $SRC_INSTANCE ]] || error <<< "Source and target instance name must differ!" || return

	log <<< ""
	info <<< "Cloning **@$SRC_INSTANCE** to **@$NEWNAME** ..."

	INSTANCE="$NEWNAME"
	Core.Instance::select
	Core.Instance::isInstance && error <<< "Instance **@$NEWNAME** already exists!" && return

	MSM_SKIP_FIREWALL=1 Core.Instance::create || return

	# Overlay the source instance's own config (presets, passwords, etc.) on
	# top of the fresh template that ::create just laid down
	cp -rf "$SRC_CFGDIR"/. "$INSTCFGDIR/" 2>/dev/null

	# The copied config still has the source's port - reassign a fresh one
	# and open the firewall for THAT one (not the throwaway one ::create
	# assigned before we overwrote its config above)
	try App::assignInstancePort
	try App::allowFirewallPorts

	success <<< "Cloned **@$SRC_INSTANCE** to **@$NEWNAME**. Review **$INSTCFGDIR/server.conf** before starting it."
)


Core.Instance::importFrom () (
	[[ $1 ]] || return
	log <<< ""
	log <<< "Trying to import instances from $1 ..."
	i=0

	INSTANCES="$(
		ssh "$1" \
			MSM_REMOTE=1 APP=$APP \
			"$THIS_COMMAND" list-instances
	)"

	[[ $INSTANCES ]] || error <<-EOF || return
		Host **$1** has no instances to import!
	EOF

	for INSTANCE in $INSTANCES; do
		Core.Instance::select
		if Core.Instance::isValidDir; then
			(( i++ ))
			mkdir -p "$INSTANCE_DIR/msm.d"
			echo $APP > "$INSTANCE_DIR/msm.d/app"
			echo "$1" > "$INSTANCE_DIR/msm.d/host"
			out <<< "    Imported **$INSTANCE_TEXT** ..."
		else
			out <<< "    $INSTANCE_TEXT already exists locally."
		fi
	done

	success <<< "Imported $i new instances from $1."
)
