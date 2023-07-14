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

          publicURL = mkOption {
            type = types.str;
            description = "Public url.";
          };

          publicIPs = mkOption {
            type = types.listOf types.str;
            description = "Public IPs (for jvb).";
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
              sha256 = "sha256-XdRApyabcShLiES03igpO0/wVrR1fRFtLt7CZhCPb8w=";
            };
            namespace = cfg.namespace;
            values = {
              publicURL = cfg.publicURL;
              enableAuth = true;
              enableGuests = true;
              jvb.publicIPs = cfg.publicIPs;
              jvb.service.type = "NodePort";
              jvb.nodePort = 31293;
              jvb.UDPPort = 31293;
              jvb.service.externalIPs = cfg.publicIPs;
              jicofo.xmpp.password = "Y9KY12iq2Z";
              jvb.xmpp.password = "59gGb3wMs2";
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
