{
  inputs = {
    nixpkgs.url = "path:/home/matejc/workarea/nixpkgs";
    kubenix = {
      url = "github:hall/kubenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {self, ... }@inputs: let
    system = "x86_64-linux";
    pkgs = inputs.nixpkgs.legacyPackages.${system};

    deployScript = pkgs.writeScript "deploy.sh" ''
      #!${pkgs.stdenv.shell}
      set -e
      ${pkgs.kubectl}/bin/kubectl \
        --kubeconfig "${result.config.kubernetes.kubeconfig}" \
        apply -f "${result.config.kubernetes.result}" $@

      ${pkgs.kubectl}/bin/kubectl \
        --kubeconfig "${result.config.kubernetes.kubeconfig}" \
        delete all --all-namespaces \
        -l kubenix/hash,kubenix/hash!=${result.config.kubernetes.generated.labels."kubenix/hash"} $@
    '';

    vars = import ./secrets/default.nix;

    result = inputs.kubenix.evalModules.${system} {
      module = { kubenix, ... }: {
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
        ];

        kubenix.project = "matejc";
        kubernetes.version = "1.23";
        kubernetes.kubeconfig = "${vars.kubeconfig}";
        docker.registry.url = "docker.io";

        submodules.instances = {
          searxng = {
            submodule = "searxng";
            args = {
              baseUrl = "https://${vars.searxng.domainName}";
              secretKey = vars.searxng.secretKey;
            };
          };
          jitsi = {
            submodule = "jitsi";
            args = {
              timeZone = "Europe/Helsinki";
              publicURL = "https://${vars.jitsi.domainName}";
              publicIP = vars.clusterIP;
            };
          };
          playground1 = {
            submodule = "jupyenv";
            args = {
              token = vars.jupyenv.playground1.token;
            };
          };
          syncthing = {
            submodule = "syncthing";
            args = { };
          };
          tailscale = {
            submodule = "tailscale";
            args.serviceCidr = vars.serviceCidr;
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
                    service = "http://searxng.default:8080";
                  }
                  {
                    hostname = vars.jitsi.domainName;
                    service = "http://jitsi-jitsi-meet-web.default:80";
                  }
                  {
                    hostname = vars.jupyenv.playground1.domainName;
                    service = "http://jupyenv-playground1.jupyenv-playground1:8080";
                  }
                  { service = "http_status:404"; }
                ];
              };
            };
          };
        };
      };
    };
  in {
    packages.${system} = {
      default = result.config.kubernetes.result;
      images = result.config.docker.copyScript;
      deploy = deployScript;
    };
  };
}
