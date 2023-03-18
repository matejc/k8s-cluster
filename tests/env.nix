{ config
, lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
{
  imports = with kubenix.modules; [
    k8s
    helm
    submodules
    ./modules/searxng.nix
  ];

  kubenix.project = "test";

  submodules.instances = {
    searxng = {
      submodule = "searxng";
      args = {
        baseUrl = "http://searxng.default:8080";
        secretKey = "test";
      };
    };
  };
}
