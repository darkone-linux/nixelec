
# this is Work In Progress configuration.nix for cross-compiling
# a Kodi appliance based on the Odroid C2

{ config, lib, pkgs, ... }:

let
  secrets = import ./secrets.nix;
  xjson-to-xml = pkgs.buildPackages.callPackage ./xjson-to-xml {};
  attrsetToXml = roottag : attrs : name : pkgs.stdenv.mkDerivation {
    inherit name;
    phases = ["installPhase"];
    installPhase =
      let json = pkgs.writeText "${name}.json" (builtins.toJSON attrs);
      in "${xjson-to-xml}/bin/xjson-to-xml ${roottag} < ${json} > $out";
  };
  sources =
    let path = p : { "@" = { pathversion = "1"; }; "#" = p; };
        default = { "@" = { "pathversion" = "1"; };};
        mkSource = folder: {
          name = folder;
          path = path "${secrets.mediasource.url}/${folder}/";
          allowsharing = "true";
        };
    in {
      video = {
        inherit default;
        source = [(mkSource "tvshows")
                  (mkSource "video")
                  (mkSource "movies")];
      };
      music = {
        inherit default;
        source = [(mkSource "music")];
      };
    };

  # perhaps we could automate configuring the source content type using a
  # bit of sql, but we need this to be executed (1) after kodi has created
  # the database and the paths, (2) while kodi is not running
  # in userdata/Database/MyVideos119.db
  # update table path set    strContent ='tvshows', strScraper='metadata.tvshows.themoviedb.org.python',  strSettings=' where strPath='https://example.com/media/tvshows/';

  advancedSettings = {
    audiooutput= {
      audiodevice = "ALSA:kodi";
    };
    services = {
      esallinterfaces = "true";
      webserver = "true";
      webserverport = "8080";
      webserverauthentication = "true";
      webserverusername = secrets.http.username;
      webserverpassword = secrets.http.password;
      webserverssl = "false";
    };
  };
in {
  nixpkgs.overlays = [
    (self: super: {

      atk = super.atk.overrideAttrs(o: {
        nativeBuildInputs = o.nativeBuildInputs ++
                            [ self.pkg-config self.buildPackages.stdenv.cc ];
      });

      # gobject-introspection =
      #   let moreCross = builtins.toFile "cross-exe-wrapper.conf" ''
      #       [binaries]
      #       exe_wrapper = '/nix/store/4s5s0bgp6708nnyl9zbc7fa6s8c5xh59-qemu-6.0.0/bin/qemu-aarch64'
      #     '';
      #       d = super.gobject-introspection.overrideAttrs(o: {
      #         mesonFlags =  [ "-Dcairo=disabled"
      #                         "-Ddoctool=disabled"
      #                         "--cross-file=${moreCross}" ];
      #         nativeBuildInputs = o.nativeBuildInputs ++
      #                             [ self.buildPackages.stdenv.cc ];
      #       });
      #   in d.override {
      #     x11Support = false;
      #     # python38 fails on aarch64, "No module named 'giscanner._giscanner'"
      #     python3 = self.python37;
      #   };

      gdk-pixbuf= (super.gdk-pixbuf.overrideAttrs(o:{
        preInstall = "mkdir -p $out/share/doc $installedTests/foo";
        mesonFlags = o.mesonFlags ++ [
          "-Dgtk_doc=false"
        ];
      })).override { doCheck = false; gobject-introspection = null;};

      harfbuzz = (super.harfbuzz.overrideAttrs(o: {
        doCheck = false;
        mesonFlags = ["-Dgobject=disabled"
                      "-Dicu=disabled"
                      "-Dintrospection=disabled"
                     ];
      })).override({gobject-introspection = null;});

      kodi = let k = super.kodi.overrideAttrs(o:{
        preConfigure = ''
          cmakeFlagsArray+=("-DCORE_PLATFORM_NAME=gbm")
          # Need these tools on the build system when cross compiling,
          # hacky, but have found no other way.
          CXX=$CXX_FOR_BUILD LD=ld make -C tools/depends/native/JsonSchemaBuilder
          cmakeFlags+=" -DWITH_JSONSCHEMABUILDER=$PWD/tools/depends/native/JsonSchemaBuilder/bin"
          CXX=$CXX_FOR_BUILD LD=ld make EXTRA_CONFIGURE= -C tools/depends/native/TexturePacker
          cmakeFlags+=" -DWITH_TEXTUREPACKER=$PWD/tools/depends/native/TexturePacker/bin"
        '';

      }); in
               k.override {
                 x11Support  = false;
                 dbusSupport  = false;
                 joystickSupport = false;
                 nfsSupport = false;
                 pulseSupport  = false;
                 sambaSupport  = false;
                 udevSupport = false;
                 usbSupport = false;
                 vdpauSupport = false;
                 gbmSupport = true;

                 #jre_headless = self.buildPackages.adoptopenjdk-openj9-bin-11;
                 jre_headless = self.buildPackages.semeru-bin-11;
                 lirc = null;
               };

      restoreKodiConfig = pkgs.writeScript "restore-kodi-config.sh" ''
        #!${self.pkgs.bash}/bin/bash
        mkdir -p /home/kodi/.kodi/userdata
        cat ${attrsetToXml "advancedsettings" advancedSettings "advancedsettings.xml"} > /home/kodi/.kodi/userdata/advancedsettings.xml
        cat ${attrsetToXml "sources" sources "sources.xml"} > /home/kodi/.kodi/userdata/sources.xml
      '';

      libcec = super.libcec.overrideAttrs(o:{
        cmakeFlags =  [ "-DHAVE_LINUX_API=1" ];
      });

      linuxPackages = super.linuxPackages_latest.extend (lpself: lpsuper: {
        kernel = super.linuxPackages_latest.kernel.override {
          extraConfig = ''
             STAGING y
             STAGING_MEDIA y
             VIDEO_MESON_VDEC m
          '';
        };
      });

#      mesa =
#        (super.mesa.overrideAttrs (o:{
#          mesonFlags =
#            let moreCross = self.writeText "cross-exe-wrapper.conf" ''
#            [binaries]
#            llvm-config = '${self.llvmPackages_11.llvm.dev}/bin/llvm-config'
#            cmake = '${self.buildPackages.cmake}/bin/cmake'
#            exe_wrapper = '/nix/store/4s5s0bgp6708nnyl9zbc7fa6s8c5xh59-qemu-6.0.0/bin/qemu-aarch64'
#        ''; in
#              ["-Dgallium-drivers=[lima,panfrost]"
#               "--cross-file=${moreCross}"
#              ] ++ o.mesonFlags;
#        }));

      pango = null;

      # make-tarball is hardcoded to use pixz, but waqnts a host
      # version not a build version
      pixz = super.buildPackages.pixz;

      rtmpdump = super.rtmpdump.overrideAttrs(o:{
        makeFlags = o.makeFlags ++ [
          "CC=${self.stdenv.cc.targetPrefix}cc"
          "AR=${self.stdenv.cc.targetPrefix}ar"
        ];
      });

      tdb = super.tdb.overrideAttrs(o: {
        nativeBuildInputs = o.nativeBuildInputs ++ [ self.python3 ];
      });
    })
  ];

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix

      # need this for deploying to the odroid
      <nixpkgs/nixos/modules/installer/sd-card/sd-image.nix>
    ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  sdImage.populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';
  sdImage.populateFirmwareCommands = "";
  sdImage.compressImage = false;
  sdImage.postBuildCommands =
    let u = pkgs.ubootOdroidC2;
        bl1 = "${u}/bl1.bin.hardkernel";
        uboot = "${u}/u-boot.gxbb"; in
      # https://archlinuxarm.org/packages/aarch64/uboot-odroid-c2-mainline/files/sd_fusing.sh?raw
      ''
        dd if=${bl1} of=$img conv=fsync,notrunc bs=1 count=442
        dd if=${bl1} of=$img conv=fsync,notrunc bs=512 skip=1 seek=1
        dd if=${uboot} of=$img conv=fsync,notrunc bs=512 seek=97
      '';

  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible = {
    enable = true;
    configurationLimit = 0;
  };

  # override systemd core file processing, which grinds the box to a
  # halt (load av > 11)
  boot.kernel.sysctl."kernel.core_pattern" = "/dev/null";

  environment.systemPackages = [ pkgs.libcec ];

  networking.hostName = "artmedia"; # Define your hostname.

  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;

  systemd.services.kodi = {
    wantedBy = [ "multi-user.target"];
    serviceConfig = {
      WorkingDirectory = "/home/kodi";
      User = "kodi";
      ExecStartPre = "${pkgs.restoreKodiConfig}";
      ExecStart = ''
        ${pkgs.kodi}/bin/kodi  --windowing=gbm
        '';
    };
  };

  # Enable sound.
  #sound.extraConfig = ''
  #  pcm.kodi {
  #      type plug
  #      slave {
  #          pcm "hw:0"
  #          rate 44100
  #          format S16_LE
  #      }
  #  }
  #  defaults.namehint.showall on
  #  defaults.namehint.extended on
  #  defaults.pcm.rate_converter "speexrate"
  #'';

  # Select internationalisation properties.
  i18n.defaultLocale = "fr_FR.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = lib.mkForce "fr";
    useXkbConfig = true; # use xkb.options in tty.
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.nixos = {
    isNormalUser = true;
    initialPassword = "pass";
    extraGroups = [ "weston-launch" "wheel" "video" "audio"]; # Enable ‘sudo’ for the user.
  };
  security.sudo.wheelNeedsPassword = false;

  users.users.kodi = {
    isNormalUser = true;
    extraGroups = [ "input" "video" "audio"];
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [
    "${builtins.getEnv "HOME"}/.ssh/authorized_keys"
    "${builtins.getEnv "HOME"}/.ssh/id_ed25519.pub"
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  system.stateVersion = "25.05"; # Did you read the comment?

  hardware.opengl.enable = true;

  networking.firewall = {
    # for the Kodi web interface
    allowedTCPPorts = [ 8080 ];
    allowedUDPPorts = [ 8080 ];
  };
}
