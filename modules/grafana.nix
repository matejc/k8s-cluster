{ config
, lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
let
  cfg = config.apps.grafana;

  agentManifests = fetchurl {
    url = "https://raw.githubusercontent.com/grafana/agent/v0.27.1/production/kubernetes/agent-bare.yaml";
    sha256 = "sha256-iAPorIfzBiPSE4DznRJUK6oO/T5T76qtzRaUkwlkpG0=";
  };

  lokiManifests = fetchurl {
    url = "https://raw.githubusercontent.com/grafana/agent/v0.27.1/production/kubernetes/agent-loki.yaml";
    sha256 = "sha256-/rQNLvs2jO8atCKqwv9ZMkl5tIOV/hZ2kdm8Z1z2wcc=";
  };

  render = path:
    imap (i: s: builtins.toFile "${toString i}.yaml" s) (remove [] (
      builtins.split "---" (builtins.readFile (
        runCommand "render.sh" {
          buildInputs = [ envsubst ];
        } ''
          export NAMESPACE=${cfg.namespace}
          cat "${path}" | envsubst >$out
        ''
      ))
    ));
in {
  options.apps.grafana = {
    enable = mkEnableOption "Whether to enable Grafana.";

    namespace = mkOption {
      default = "default";
      type = types.str;
      description = "Target namespace.";
    };

    templateYaml = mkOption {
      type = types.path;
      description = "Template from <you>.grafana.com";
    };
  };

  config = mkIf cfg.enable {
    kubernetes.resources.namespaces.${cfg.namespace} = { };

    kubernetes.helm.releases.kube-state-metrics = {
      chart = kubenix.lib.helm.fetch {
        chart = "kube-state-metrics";
        repo = "https://prometheus-community.github.io/helm-charts";
        sha256 = "sha256-JshSIkvlMbw3cMZ+/nJO/o+XlHaBHBq7M4+rDbwzk2M=";
      };
      namespace = cfg.namespace;
      values = {
        image.tag = "v2.4.2";
      };
    };
    kubernetes.helm.releases.prometheus-node-exporter = {
      chart = kubenix.lib.helm.fetch {
        chart = "prometheus-node-exporter";
        repo = "https://prometheus-community.github.io/helm-charts";
        sha256 = "sha256-pRtX3yHAJU3x5pG9lS8tha0qyTtSS0i5cuvSPyw2ap0=";
      };
      namespace = cfg.namespace;
      values = { };
    };
    kubernetes.imports = (render agentManifests) ++ (render cfg.templateYaml);
    kubernetes.resources.statefulSets.grafana-agent.spec.volumeClaimTemplates = mkForce [{
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "agent-wal";
        namespace = cfg.namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Gi";
      };
    }];
  };
}
