# Builds an zfs image containing a populated /nix/store with the closure
# of store paths passed in the storePaths parameter, in addition to the
# contents of a directory that can be populated with commands. The
# generated image is sized to only fit its contents, with the expectation
# that a script resizes the filesystem at boot time.
{
  pkgs,
  lib,
  # List of derivations to be included
  storePaths,
  # Whether or not to compress the resulting image with zstd
  compressImage ? false,
  zstd,
  # Shell commands to populate the ./files directory.
  # All files in that directory are copied to the root of the FS.
  populateImageCommands ? "",
  zpoolName,
  defaultZpoolName ? "nixos-tank",
  # , uuid ? "44444444-4444-4444-8888-888888888888"
  perl,
  zfsUnstable,
}: let
  sdClosureInfo = pkgs.buildPackages.closureInfo {rootPaths = storePaths;};
in
  pkgs.stdenv.mkDerivation {
    name = "zfs-fs.img${lib.optionalString compressImage ".zst"}";

    nativeBuildInputs =
      [perl zfsUnstable]
      ++ lib.optional compressImage zstd;

    buildCommand = ''
      ${
        if compressImage
        then "img=temp.img"
        else "img=$out"
      }
      (
      mkdir -p ./files
      ${populateImageCommands}
      )

      echo "Preparing store paths for image..."

      # Create nix/store before copying path
      mkdir -p ./rootImage/nix/store

      xargs -I % cp -a --reflink=auto % -t ./rootImage/nix/store/ < ${sdClosureInfo}/store-paths
      (
        GLOBIGNORE=".:.."
        shopt -u dotglob

        for f in ./files/*; do
            cp -a --reflink=auto -t ./rootImage/ "$f"
        done
      )

      # Also include a manifest of the closures in a format suitable for nix-store --load-db
      cp ${sdClosureInfo}/registration ./rootImage/nix-path-registration

      # Make a crude approximation of the size of the target image.
      # If the script starts failing, increase the fudge factors here.
      numInodes=$(find ./rootImage | wc -l)
      numDataBlocks=$(du -s -c -B 4096 --apparent-size ./rootImage | tail -1 | awk '{ print int($1 * 1.10) }')
      bytes=$((2 * 4096 * $numInodes + 4096 * $numDataBlocks))
      echo "Creating an ZFS image of $bytes bytes (numInodes=$numInodes, numDataBlocks=$numDataBlocks)"

      truncate -s $bytes $img
      zpool create \
        -O mountpoint=none \
        -O atime=off \
        -O compression=lz4 \
        -O xattr=sa \
        -O acltype=posixacl \
        -o ashift=12 \
        ${defaultZpoolName} \
        $img

      create_and_mount() {
        local name="$1"
        local mountpoint="$2"
        local dataset="${defaultZpoolName}/$1"
        zfs create -o mountpoint=none "$dataset"
        mkdir -p "$mountpoint"
        mount.zfs "$dataset" "$mountpoint"
      }

      create_and_mount root /
      create_and_mount nix /nix
      create_and_mount var /var
      create_and_mount home /home

      # We may want to shrink the file system and resize the image to
      # get rid of the unnecessary slack here--but see
      # https://github.com/NixOS/nixpkgs/issues/125121 for caveats.

      if [ ${builtins.toString compressImage} ]; then
        echo "Compressing image"
        zstd -v --no-progress ./$img -o $out
      fi
    '';
  }
