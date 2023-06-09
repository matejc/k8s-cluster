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

          serviceCidr = mkOption {
            type = types.str;
            description = "Service CIDR.";
          };

          authKey = mkOption {
            type = types.str;
            description = "Auth key.";
          };
        };

        config = {
          submodule = {
            name = "tailscale";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.resources.serviceAccounts.tailscale = {
            metadata.namespace = cfg.namespace;
          };
          kubernetes.resources.roles.tailscale = {
            metadata.namespace = cfg.namespace;
            rules = [
              {
                apiGroups = [ "" ];
                resources = [ "secrets" ];
                verbs = [ "create" ];
              }
              {
                apiGroups = [ "" ];
                resourceNames = [ "tailscale-auth" ];
                resources = [ "secrets" ];
                verbs = [ "get" "update" "patch" ];
              }
            ];
          };
          kubernetes.resources.roleBindings.tailscale = {
            metadata.namespace = cfg.namespace;
            roleRef = {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Role";
              name = "tailscale";
            };
            subjects = [{
              kind = "ServiceAccount";
              name = "tailscale";
            }];
          };
          kubernetes.resources.deployments.tailscale = {
            metadata.labels.app = "tailscale";
            metadata.namespace = cfg.namespace;
            spec = {
              replicas = 1;
              selector.matchLabels.app = "tailscale";
              template = {
                metadata.labels.app = "tailscale";
                spec = {
                  containers = [{
                    env = [
                      {
                        name = "TS_KUBE_SECRET";
                        value = "tailscale-auth";
                      }
                      {
                        name = "TS_USERSPACE";
                        value = "true";
                      }
                      {
                        name = "TS_AUTHKEY";
                        valueFrom = {
                          secretKeyRef = {
                            key = "TS_AUTHKEY";
                            name = "tailscale-auth";
                            optional = true;
                          };
                        };
                      }
                      {
                        name = "TS_ROUTES";
                        value = cfg.serviceCidr;
                      }
                      {
                        name = "TS_EXTRA_ARGS";
                        value = "--accept-dns=false --advertise-routes=${cfg.serviceCidr} --advertise-exit-node";
                      }
                    ];
                    image = "ghcr.io/tailscale/tailscale:latest";
                    imagePullPolicy = "Always";
                    name = "tailscale";
                    securityContext = {
                      runAsGroup = 1000;
                      runAsUser = 1000;
                    };
                  }];
                  serviceAccountName = "tailscale";
                };
              };
            };
          };
          kubernetes.resources.secrets.tailscale-auth = {
            stringData = {
              TS_AUTHKEY = cfg.authKey;
            };
          };
        };
      };
    }
  ];
}
