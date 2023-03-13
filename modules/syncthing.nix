{ config
, lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
{
  submodules.imports = [
    {
      module = {
        name,
        config,
        ...
      }: let
        cfg = config.submodule.args;
      in {
        imports = with kubenix.modules; [submodule helm k8s];

        options.submodule.args = {
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

        config = {
          submodule = {
            name = "syncthing";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };


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
      };
    }
  ];
}
