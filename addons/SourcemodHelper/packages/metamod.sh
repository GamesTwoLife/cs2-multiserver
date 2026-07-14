#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

SourcemodPackage.metamod::download () {
	# NOTE: CS2 (Source 2) needs the 2.x branch (has metamod.2.cs2.so). The legacy
	# 1.1x branch is for Source 1 games (CS:GO, TF2, ...) and does NOT support CS2 at all.
	SourcemodHelper::unpackTar \
		https://github.com/alliedmodders/metamod-source/releases/download/2.0.0.1406/mmsource-2.0.0-git1406-linux.tar.gz \
		18c9231b8b7de14add24b0fcc5b3e6d27b8d894a9182cb04cfb6c2770573f514
}
