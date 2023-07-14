{ lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
let
  vars = import ./secrets/default.nix;
in {
  imports = with kubenix.modules; [
    k8s
    helm
    docker
    submodules
    ./modules/searxng.nix
    ./modules/tunnel.nix
    ./modules/tailscale.nix
    ./modules/syncthing.nix
    ./modules/jitsi.nix
    ./modules/jupyenv.nix
    ./modules/necesse.nix
  ];

  kubenix.project = "k3s";
  kubernetes.version = "1.25";
  kubernetes.kubeconfig = "${vars.kubeconfig}";
  docker.registry.url = "docker.io";

  submodules.instances = {
    searxng = {
      submodule = "searxng";
      args = {
        namespace = "searxng";
        baseUrl = "https://${vars.searxng.domainName}";
        secretKey = vars.searxng.secretKey;
      };
    };
    jitsi = {
      submodule = "jitsi";
      args = {
        namespace = "jitsi";
        timeZone = "Europe/Helsinki";
        publicURL = "https://${vars.jitsi.domainName}";
        publicIPs = vars.externalIPs;
      };
    };
    #playground1 = {
    #  submodule = "jupyenv";
    #  args = {
    #    token = vars.jupyenv.playground1.token;
    #  };
    #};
    syncthing = {
      submodule = "syncthing";
      args = {
        namespace = "syncthing";
      };
    };
    tailscale = {
      submodule = "tailscale";
      args = {
        serviceCidr = vars.serviceCidr;
        authKey = vars.tailscale.authKey;
      };
    };
    tunnel = {
      submodule = "cloudflared";
      args = {
        credentials = vars.tunnel.credentials;
        settings = {
          tunnel = vars.tunnel.name;
          ingress = [
            {
              hostname = vars.searxng.domainName;
              service = "http://searxng.searxng:8080";
            }
            {
              hostname = vars.jitsi.domainName;
              service = "http://jitsi-jitsi-meet-web.jitsi:80";
            }
            { service = "http_status:404"; }
          ];
        };
      };
    };
    #skyrim = {
    #  submodule = "tilted-online";
    #  args = {
    #    namespace = "skyrim";
    #    settings = vars.skyrim.settings;
    #    loadorder = vars.skyrim.loadorder;
    #    publicIPs = vars.externalIPs;
    #  };
    #};
    #necesse = {
    #  submodule = "necesse";
    #  args = {
    #    namespace = "necesse";
    #    settings = vars.necesse;
    #  };
    #};
  };
}
