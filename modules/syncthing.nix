{ config
, lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
let
  cfg = config.apps.syncthing;
in {
  options.apps.syncthing = {
    enable = mkEnableOption "Whether to enable Syncthing.";

    namespace = mkOption {
      default = "default";
      type = types.str;
      description = "Target namespace.";
    };

    storageSize = mkOption {
      type = types.str;
      default = "50Gi";
      description = "PV size.";
    };
  };

  config = lib.mkIf cfg.enable {
    kubernetes.helm.releases.syncthing = {
      chart = kubenix.lib.helm.fetch {
        chart = "syncthing";
        repo = "https://charts.truecharts.org/";
        sha256 = "sha256-gnkZJzABBcAqUR7VRwRoNK3oEHTCRuxOxdxbpi6YxSI=";
      };
      namespace = cfg.namespace;
      values = {
        manifests.enabled = false;
        controler.enabled = false;
        portal.enabled = false;
        persistence.config = {
          size = cfg.storageSize;
        };
      };
    };
  };
}
