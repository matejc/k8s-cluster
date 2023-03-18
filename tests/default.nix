{
  lib,
  pkgs,
  kubenix,
  test,
  ...
}:
let in {
  imports = [ kubenix.modules.test ];

  test = {
    name = "example";
    description = "can reach deployment";
    script = ''
      @pytest.mark.applymanifest('${test.kubernetes.resultYAML}')
      def test_deployment(kube):
          kube.wait_for_registered(timeout=30)
          deployments = kube.get_deployments()
          deploy = deployments.get('searxng')
          assert deploy is not None
          status = deploy.status()
          assert status.readyReplicas == 1
    '';
  };
}
