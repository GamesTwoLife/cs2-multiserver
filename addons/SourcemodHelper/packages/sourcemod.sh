#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

SourcemodPackage.sourcemod::download () {
	SourcemodHelper::unpackTar \
		https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7245/sourcemod-1.12.0-git7245-linux.tar.gz \
		151a24bec2c6ffccc81a453e95d8b09d15e5b7fab3f61412327d1d17e3d734dd
}
