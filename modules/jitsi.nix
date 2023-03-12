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
          enable = mkEnableOption "Whether to enable Jitsi meet.";

          namespace = mkOption {
            default = "default";
            type = types.str;
            description = "Target namespace.";
          };

          publicURL = mkOption {
            type = types.str;
            description = "Public url.";
          };

          publicIP = mkOption {
            type = types.str;
            description = "Public IP (for jvb).";
          };

          timeZone = mkOption {
            type = types.str;
            description = "Time zone.";
          };
        };

        config = {
          submodule = {
            name = "jitsi";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.helm.releases.jitsi = {
            chart = kubenix.lib.helm.fetch {
              chart = "jitsi-meet";
              repo = "https://jitsi-contrib.github.io/jitsi-helm/";
              sha256 = "sha256-5LmozjI65A/c84rnTe/I4NmQQM3a1OpZtqMGTL83RAo=";
            };
            namespace = cfg.namespace;
            values = {
              publicURL = cfg.publicURL;
              enableAuth = true;
              enableGuests = true;
              jvb.publicIPs = [ cfg.publicIP ];
              jvb.service.type = "NodePort";
              jvb.service.nodePort = 10000;
              jvb.service.externalIPs = [ cfg.publicIP ];
              web.extraEnvs = {
                ENABLE_WELCOME_PAGE = "0";
              };
              prosody.extraEnvs = [ {
                name = "ENABLE_AUTO_LOGIN";
                value = "1";
              } ];
              tz = cfg.timeZone;
            };
          };
        };
      };
    }
  ];
}
