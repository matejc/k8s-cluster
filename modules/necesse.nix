{ lib
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
        imports = with kubenix.modules; [submodule k8s];

        options.submodule.args = {
          namespace = mkOption {
            default = "default";
            type = types.str;
            description = "Target namespace.";
          };

          settings = mkOption {
            type = types.attrs;
            description = "Directly mapped as environment variables.";
          };
        };

        config = {
          submodule = {
            name = "necesse";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.resources.deployments.necesse = {
            spec = {
              replicas = 1;
              selector = { matchLabels = { app = "necesse"; }; };
              template = {
                metadata = { labels = { app = "necesse"; }; };
                spec = {
                  containers = [ {
                    name = "server";
                    image = "brammys/necesse-server:latest";
                    imagePullPolicy = "Always";
                    volumeMounts = [ {
                      mountPath = "/necesse/saves";
                      name = "saves";
                    } ];
                    env = mapAttrsToList nameValuePair cfg.settings;
                    ports = [
                      {
                        protocol = "UDP";
                        containerPort = 14159;
                      }
                    ];
                    resources = {
                      requests = {
                        memory = "2Gi";
                        cpu = "1750m";
                      };
                      limits = {
                        memory = "2Gi";
                        cpu = "2000m";
                      };
                    };
                  } ];
                  volumes = [ {
                    name = "saves";
                    persistentVolumeClaim.claimName = "necesse";
                  } ];
                };
              };
            };
          };

          kubernetes.resources.persistentVolumeClaims.necesse.spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "5Gi";
          };

          kubernetes.resources.services.necesse.spec = {
            selector.app = "necesse";
            type = "NodePort";
            ports = [{
              protocol = "UDP";
              port = 14159;
              targetPort = 14159;
              nodePort = 31337;
            }];
          };
        };
      };
    }
  ];
}
