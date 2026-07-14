#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

SourcemodPackage.counterstrikesharp::download () {
	SourcemodHelper::unpackZip \
		https://github.com/roflmuffin/CounterStrikeSharp/releases/download/v1.0.371/counterstrikesharp-with-runtime-linux-1.0.371.zip \
		447f699d574348c9ffafc3d54a88363f29cd7ecba3d8e52adcccd9201812d01d
}
