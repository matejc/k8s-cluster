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
        defaultSettings = {
          credentials-file = "/etc/cloudflared/creds/credentials.json";
          metrics = "0.0.0.0:2000";
          no-autoupdate = true;
          # The `ingress` block tells cloudflared which local service to route incoming
          # requests to. For more about ingress rules, see
          # https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/ingress
          # Remember, these rules route traffic from cloudflared to a local service. To route traffic
          # from the internet to cloudflared, run `cloudflared tunnel route dns <tunnel> <hostname>`.
          # E.g. `cloudflared tunnel route dns example-tunnel tunnel.example.com`.
          ingress = [];
        };
      in {
        imports = with kubenix.modules; [submodule k8s];

        options.submodule.args = {
          namespace = mkOption {
            default = "default";
            type = types.str;
            description = "Target namespace.";
          };

          credentials = mkOption {
            type = types.attrs;
            description = "Keys/values from credentials.json (got from creating tunnel with cloudflared command)";
          };

          settings = mkOption {
            type = types.attrs;
            description = "As config.yaml passed to cloudflared container.";
          };
        };

        config = {
          submodule = {
            name = "cloudflared";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.resources.deployments.cloudflared = {
            spec = {
              replicas = 1;
              selector = { matchLabels = { app = "cloudflared"; }; };
              template = {
                metadata = { labels = { app = "cloudflared"; }; };
                spec = {
                  containers = [ {
                    name = "cloudflared";
                    image = "cloudflare/cloudflared:2023.2.1";
                    args = [ "tunnel" "--config" "/etc/cloudflared/config/config.yaml" "run" ];
                    livenessProbe = {
                      failureThreshold = 1; httpGet = { path = "/ready"; port = 2000; };
                      initialDelaySeconds = 10; periodSeconds = 10;
                    };
                    volumeMounts = [ {
                      mountPath = "/etc/cloudflared/config";
                      name = "config";
                      readOnly = true;
                    } {
                      mountPath = "/etc/cloudflared/creds";
                      name = "creds";
                      readOnly = true;
                    } ];
                  } ];
                  volumes = [ {
                    name = "creds";
                    secret = {
                      secretName = "tunnel-credentials";
                    };
                  } {
                    configMap = {
                      items = [ {
                        key = "config.yaml";
                        path = "config.yaml";
                      } ];
                      name = "cloudflared";
                    };
                    name = "config";
                  } ];
                };
              };
            };
          };

          kubernetes.resources.secrets.tunnel-credentials = {
            stringData = {
              "credentials.json" = builtins.toJSON cfg.credentials;
            };
          };

          kubernetes.resources.configMaps.cloudflared = {
            data = {
              "config.yaml" = builtins.toJSON (recursiveUpdate defaultSettings cfg.settings);
            };
          };
        };
      };
    }
  ];
}
