#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

# Runs after a successful `cs2-server update`. Checks GitHub for newer builds of
# the pinned plugin packages and, with the user's explicit consent, updates the
# pin (URL + checksum) in the corresponding packages/*.sh file. SourceMod is
# intentionally not checked here - it has no functional CS2 build to update to.
::registerHook after~Core.BaseInstallation::afterUpdate SourcemodHelper::checkForUpdates

SourcemodHelper::checkForUpdates () {
	log <<< ""
	out <<< "Checking for newer Metamod:Source / CounterStrikeSharp / SwiftlyS2 builds ..."

	# repo, "jq test() regex for tag_name", "jq test() regex for asset filename"
	SourcemodHelper::checkPackageUpdate metamod \
		alliedmodders/metamod-source '^2\.' 'linux\.tar\.gz$'
	SourcemodHelper::checkPackageUpdate counterstrikesharp \
		roflmuffin/CounterStrikeSharp '.' 'with-runtime-linux.*\.zip$'
	SourcemodHelper::checkPackageUpdate swiftlys2 \
		swiftly-solution/swiftlys2 '.' 'linux.*with-runtimes\.zip$'
}


SourcemodHelper::checkPackageUpdate () {
	local name="$1" repo="$2" tagFilter="$3" assetFilter="$4"
	local pkgdir="$(::moduleDir SourcemodHelper)/packages"
	local pkgfile="$pkgdir/$name.sh"
	[[ -f $pkgfile ]] || return 0

	local currentUrl
	currentUrl="$(grep -oE 'https://[^[:space:]\\]+' "$pkgfile" | head -1)"

	local json
	json="$(wget -qO- "https://api.github.com/repos/$repo/releases?per_page=50")" || {
		catwarn <<< "Could not check for updates to **$name** (GitHub API request failed)."
		return 0
	}

	local latestUrl
	latestUrl="$(echo "$json" | jq -r --arg tf "$tagFilter" --arg af "$assetFilter" '
		[.[] | select(.draft==false) | select(.tag_name | test($tf))]
		| sort_by(.created_at) | reverse | .[0].assets[]?
		| select(.name | test($af)) | .browser_download_url
	' 2>/dev/null | head -1)"

	[[ $latestUrl ]] || return 0
	[[ $latestUrl != "$currentUrl" ]] || return 0

	out <<-EOF

		A newer **$name** build is available:
		    current: $currentUrl
		    latest:  $latestUrl
	EOF
	promptY "Update $name to this version?" || return 0

	local tmp="$(mktemp)"
	wget -O "$tmp" "$latestUrl" || {
		rm -f "$tmp"
		error <<< "Download of the new $name build failed, keeping the current pin."
		return 1
	}
	local sha
	sha="$(sha256sum "$tmp")"
	sha=${sha%% *}
	rm -f "$tmp"

	awk -v u="$latestUrl" -v s="$sha" '
		/^[[:space:]]*https:\/\// { sub(/https:\/\/[^[:space:]\\]*/, u); print; next }
		/^[[:space:]]*[0-9a-f]{64}[[:space:]]*$/ { sub(/[0-9a-f]{64}/, s); print; next }
		{ print }
	' "$pkgfile" > "$pkgfile.msm-tmp" && mv "$pkgfile.msm-tmp" "$pkgfile"

	success <<< "**$name** pin updated. It will be (re-)deployed on the next server start of any instance."
}
