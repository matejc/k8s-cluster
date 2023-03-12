{ config
, lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
let
  jupyterlabOptions =
    { name, config, lib, ... }:
    { options = {
      enable = mkEnableOption "Whether to enable JupyterLab.";

      name = mkOption {
        default = name;
        type = types.str;
        description = "Internal name of JupyterLab instance.";
      };

      namespace = mkOption {
        default = "jupyterlab-${name}";
        type = types.str;
        description = "Target namespace.";
      };

      token = mkOption {
        type = types.str;
        description = "JupyterLab access token.";
      };

      storageSize = mkOption {
        type = types.str;
        default = "2Gi";
        description = "JupyterLab PV size.";
      };
    }; };


  enabled = lib.filterAttrs (_: v: v.enable) config.apps.jupyterlab;
in {
  options.apps.jupyterlab = mkOption {
    default = { };
    type = types.attrsOf (types.submodule jupyterlabOptions);
    description = "JupyterLab configuration";
  };

  config.kubernetes = lib.mkIf (enabled != {}) (lib.mkMerge (lib.mapAttrsToList (_: cfg: {
    resources.namespaces.${cfg.namespace} = { };

    helm.releases.jupyterlab = {
      chart = kubenix.lib.helm.fetch {
        chart = "jupyter";
        repo = "https://charts.truecharts.org/";
        sha256 = "sha256-ZFMdFqgvOeBl/PtCOAhtnsO1Jtwt6TqFkWbuvZmU0Ck=";
      };
      namespace = cfg.namespace;
      values = {
        image = {
          repository = "jupyter/base-notebook";
          pullPolicy = "Always";
          tag = "latest";
        };
        minimalImage = {
          repository = "jupyter/minimal-notebook";
          pullPolicy = "Always";
          tag = "latest";
        };
        manifests.enabled = false;
        controler.enabled = false;
        portal.enabled = false;
        persistence.data = {
          size = cfg.storageSize;
        };
      };
    };

    resources.secrets."jupyterlab-${cfg.name}" = {
      metadata.namespace = cfg.namespace;
      stringData = {
        "JUPYTER_TOKEN" = cfg.token;
      };
    };

    resources.deployments.jupyterlab.spec.template.spec.containers.jupyterlab = {
      env = [{
        name = "JUPYTER_TOKEN";
        valueFrom.secretKeyRef = {
          name = "jupyterlab-${cfg.name}";
          key = "JUPYTER_TOKEN";
        };
      }];
      resources = {
        limits = {
          memory = lib.mkForce "1Gi";
          cpu = lib.mkForce "500m";
        };
      };
    };
  }) enabled));
}
