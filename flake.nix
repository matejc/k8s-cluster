{
  inputs = {
    nixpkgs.url = "path:/home/matejc/workarea/nixpkgs";
    kubenix = {
      url = "github:hall/kubenix";
      #url = "path:/home/matejc/workarea/kubenix";
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

    result = inputs.kubenix.evalModules.${system} {
      module = { kubenix, ... }: {
        imports = [
          ./env.nix
        ];
      };
    };

    #test = inputs.kubenix.evalModules.${system} {
    #  module = { kubenix, ... }: {
    #    imports = with kubenix.modules; [
    #      testing
    #    ];
    #    testing = {
    #      tests = [ ./tests ];
    #      common = [
    #        {
    #          features = ["k8s" "docker" "submodules"];
    #          options = {
    #            imports = [ ./tests/env.nix ];
    #            kubernetes.version = "1.23";
    #          };
    #        }
    #      ];
    #    };
    #  };
    #};
  in {
    packages.${system} = {
      default = result.config.kubernetes.result;
      images = result.config.docker.copyScript;
      deploy = deployScript;
      #test = test.config.testing.testScript;
    };
  };
}
