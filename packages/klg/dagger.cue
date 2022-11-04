package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/docker"
	"universe.dagger.io/bash"
)

#NixFlakeImageBuild: {
	src:             dagger.#FS
	filename:        string | *"image.tar.gz"
	flakePackageKey: string | *"container"

	outDir: _build.export.directories."/out"
	_image: docker.#Pull & {source: "nixos/nix:2.11.1"}

	// Build steps
	_build: bash.#Run & {
		input: _image.output
		export: directories: "/out": dagger.#FS
		mounts: "sources": {contents: src, dest: "/src"}

		script: contents: """
			echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
			nix build --show-trace "/src#\(flakePackageKey)"
			mkdir -p /out
			mv "$(readlink -f result)" "/out/\(filename)"
			"""
	}
}

dagger.#Plan & {
	client: filesystem: {
		".": read: contents:      dagger.#FS
		"./out": write: contents: actions.build.outDir
	}
	actions: build: #NixFlakeImageBuild & {
		src: client.filesystem.".".read.contents
	}
}
