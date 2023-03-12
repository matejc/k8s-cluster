{ config
, lib
, pkgs
, kubenix
, k8s
, ...
}:
with lib;
with pkgs;
let
  cfg = config.apps.tunnel;

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
  options.apps.tunnel = {
    enable = mkEnableOption "Whether to enable Cloudflare tunnel.";

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
    kubernetes.resources.deployments.cloudflared = {
      metadata.namespace = cfg.namespace;
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
      metadata.namespace = cfg.namespace;
      stringData = {
        "credentials.json" = builtins.toJSON cfg.credentials;
      };
    };

    kubernetes.resources.configMaps.cloudflared = {
      metadata.namespace = cfg.namespace;
      data = {
        "config.yaml" = builtins.toJSON (recursiveUpdate defaultSettings cfg.settings);
      };
    };
  };
}
