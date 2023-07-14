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

        settingsIni = ''
          [Gameplay]
          fGoldLossFactor=0
          bEnableItemDrops=false
          bEnableXpSync=true
          uTimeScale=20
          bEnableDeathSystem=true
          bSyncPlayerHomes=false
          bEnablePvp=false
          bEnableGreetings=false
          uDifficulty=${cfg.settings.Gameplay.uDifficulty}


          [LiveServices]
          bAnnounceServer=false


          [ModPolicy]
          bAllowMO2=true
          bAllowSKSE=true
          bEnableModCheck=${cfg.settings.ModPolicy.bEnableModCheck}


          [GameServer]
          sPassword=${cfg.settings.GameServer.sPassword}
          sServerName=${cfg.settings.GameServer.sServerName}
          bPremiumMode=true
          uMaxPlayerCount=${cfg.settings.GameServer.uMaxPlayerCount}
          uPort=30578
        '';
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
            description = "GameServer settings.";
          };

          loadorder = mkOption {
            type = types.str;
            description = "loadorder.txt";
          };

          publicIPs = mkOption {
            type = types.listOf types.str;
            description = "Public IPs.";
          };
        };

        config = {
          submodule = {
            name = "tilted-online";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.resources.deployments.tilted-online = {
            spec = {
              replicas = 1;
              selector = { matchLabels = { app = "tilted-online"; }; };
              template = {
                metadata = { labels = { app = "tilted-online"; }; };
                spec = {
                  containers = [ {
                    name = "server";
                    image = "tiltedphoques/st-reborn-server:latest";
                    imagePullPolicy = "Always";
                    volumeMounts = [
                      {
                        mountPath = "/home/server/config";
                        subPath = "config/";
                        name = "data";
                      }
                      {
                        mountPath = "/home/server/Data";
                        subPath = "Data/";
                        name = "data";
                      }
                      {
                        mountPath = "/home/server/logs";
                        subPath = "logs/";
                        name = "data";
                      }
                      {
                        mountPath = "/home/server/config/STServer.ini";
                        subPath = "STServer.ini";
                        name = "configs";
                        readOnly = true;
                      }
                      {
                        mountPath = "/home/server/Data/loadorder.txt";
                        subPath = "loadorder.txt";
                        name = "configs";
                        readOnly = true;
                      }
                    ];
                    ports = {
                      udp-30578 = {
                        protocol = "UDP";
                        containerPort = 30578;
                      };
                      tcp-30578 = {
                        protocol = "TCP";
                        containerPort = 30578;
                      };
                    };
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
                  volumes = [
                    {
                      name = "data";
                      persistentVolumeClaim.claimName = "tilted-online";
                    }
                    {
                      configMap = {
                        items = [ {
                          key = "STServer.ini";
                          path = "STServer.ini";
                        } {
                          key = "loadorder.txt";
                          path = "loadorder.txt";
                        } ];
                        name = "tilted-online";
                      };
                      name = "configs";
                    }
                  ];
                };
              };
            };
          };

          kubernetes.resources.persistentVolumeClaims.tilted-online.spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "5Gi";
          };

          kubernetes.resources.services.tilted-online.spec = {
            selector.app = "tilted-online";
            type = "NodePort";
            ports = {
              udp-30578 = {
                protocol = "UDP";
                port = 30578;
                targetPort = 30578;
                nodePort = 30578;
              };
              tcp-30578 = {
                protocol = "TCP";
                port = 30578;
                targetPort = 30578;
                nodePort = 30578;
              };
            };
            externalIPs = cfg.publicIPs;
          };

          kubernetes.resources.configMaps.tilted-online = {
            data = {
              "STServer.ini" = settingsIni;
              "loadorder.txt" = cfg.loadorder;
            };
          };
        };
      };
    }
  ];
}
