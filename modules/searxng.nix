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
          enable = mkEnableOption "Whether to enable SearXNG, the meta search engine.";

          namespace = mkOption {
            default = "default";
            type = types.str;
            description = "Target namespace.";
          };

          baseUrl = mkOption {
            type = types.str;
            description = "Base url.";
          };

          secretKey = mkOption {
            type = types.str;
            description = "Secret key.";
          };
        };

        config = {
          submodule = {
            name = "searxng";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.helm.releases.searxng = {
            chart = kubenix.lib.helm.fetch {
              chart = "searxng";
              repo = "https://charts.searxng.org";
              sha256 = "sha256-ovrMVk+g6fYrgUgAyI/UV7ERjImodQxzotBfbwXlL38=";
            };
            values = {
              env.INSTANCE_NAME = "searxng";
              env.BASE_URL = cfg.baseUrl;
              persistance.config.enabled = true;
              searxng.config = {
                server = {
                  secret_key = cfg.secretKey;
                  limiter = true;
                };
                redis.url = "redis://@searxng-redis:6379/0";
              };
              redis.enabled = true;
            };
          };

          kubernetes.resources.pods.searxng-redis-test-connection.spec.containers.wget = {
            command = mkForce [ "nc" ];
            args = mkForce [ "-z" "searxng-redis.${cfg.namespace}" "6379" ];
          };
        };
      };
    }
  ];
}
