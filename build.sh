#!/bin/sh

NIX_PATH=nixpkgs=$NIXPKGS_FOR_NIXELEC nix-build -A build.sdImage

