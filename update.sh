#!/bin/sh

# copy it to the target device
nix-copy-closure --to root@artmedia -v --include-outputs \
   ./result && ssh root@artmedia \
   `readlink result`/bin/switch-to-configuration switch

