#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

SourcemodPackage.swiftlys2::download () {
	SourcemodHelper::unpackZipStripTop \
		https://github.com/swiftly-solution/swiftlys2/releases/download/v1.4.3/swiftlys2-linux-v1.4.3-with-runtimes.zip \
		b60ba1823ea3bc26d6e64ed5a5d9b31e85d7f0864d5d1939f3815073ef0d4c1c
}
