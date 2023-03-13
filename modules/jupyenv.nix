{ config
, lib
, pkgs
, kubenix
, ...
}:
with lib;
with pkgs;
let
  jupyenv = import "${fetchgit {
    url = "https://github.com/tweag/jupyenv";
    rev = "96dd4876b799e706d504220f4cd2a24dbb3afb58";
    sha256 = "sha256-DEV4puCCRRf4cnpjlaZLTPrbCUZkkLSAw2JPEkIWMDQ=";
  }}/default.nix";

  paths = [
    zlib
    zstd
    stdenv.cc.cc
    curl
    openssl
    attr
    libssh
    bzip2
    libxml2
    acl
    libsodium
    util-linux
    xz
    coreutils-full
    bashInteractive
    dockerTools.usrBinEnv
    dockerTools.binSh
    dockerTools.caCertificates
  ] ++ (nonRootShadowSetup { uid = 999; user = "jupyenv"; home = "/data"; });

  nonRootShadowSetup = { user, uid, gid ? uid, home ? "/home/${user}" }: [
    (
    writeTextDir "etc/shadow" ''
      root:!x:::::::
      ${user}:!:::::::
    ''
    )
    (
    writeTextDir "etc/passwd" ''
      root:x:0:0::/root:${runtimeShell}
      ${user}:*:${toString uid}:${toString gid}::${home}:${runtimeShell}
    ''
    )
    (
    writeTextDir "etc/group" ''
      root:x:0:
      ${user}:x:${toString gid}:
    ''
    )
    (
    writeTextDir "etc/gshadow" ''
      root:x::
      ${user}:x::
    ''
    )
    (
    writeTextDir "etc/pam.d/su" ''
      #%PAM-1.0
      auth  sufficient  pam_rootok.so
      auth  include  system-auth
      account  include  system-auth
      password  include  system-auth
      session  required  pam_unix.so
    ''
    )
  ];

  buildConfigFile = cfg: pkgs.writeTextDir "share/config.py" ''
    from jupyter_server.services.kernels.kernelmanager import AsyncMappingKernelManager
    class CustomKernelManager(AsyncMappingKernelManager):
        async def start_kernel(self, *args, **kwargs):
            print("CustomKernelManager start_kernel")
            print(f"Num Kernels Running: {len(self.list_kernels())}")
            kernels = self.list_kernels()
            if len(kernels) >= ${toString cfg.maxKernels}:
                await self.shutdown_kernel(kernels[0]["id"])
            return await AsyncMappingKernelManager.start_kernel(self, *args, **kwargs)
    c.ServerApp.kernel_manager_class = CustomKernelManager
    c.ServerApp.allow_remote_access = True
  '';

  buildStartScript = cfg: writeScriptBin "start-jupyenv" ''
    #!${runtimeShell}
    set -e
    mkdir -p /data/work
    chown -R 999:999 /data/work
    cd /data

    ${shadow.su}/bin/su jupyenv -c "env JUPYTER_TOKEN=$JUPYTER_TOKEN ${cfg.package}/bin/jupyter-lab \
      --no-browser --ip=0.0.0.0 --port=8080 --notebook-dir=/data/work \
      --port-retries=0 --config=/share/config.py"
  '';

  buildJupyenv = cfg: runCommand "jupyenv-pre-build" {
    buildInputs = [ fakeroot ];
    __noChroot = true;
  } ''
    set -e
    mkdir -p $out/.jupyter/lab/share/jupyter/lab/staging
    export HOME="$out"
    cd "$out"
    fakeroot ${cfg.package}/bin/jupyter lab build
  '';

  buildImage = cfg: dockerTools.buildLayeredImage {
    name = "matejc/jupyenv";
    contents = paths ++ [(buildStartScript cfg) (buildConfigFile cfg)];
    enableFakechroot = true;
    fakeRootCommands = ''
      set -e
      mkdir -p /tmp
      chmod ugo+rwx /tmp
      mkdir -p /usr
      ln -s /bin /usr/bin

      mkdir -p /data/.jupyter/lab/share/jupyter
      ln -s ${buildJupyenv cfg}/.jupyter/lab/share/jupyter/lab /data/.jupyter/lab/share/jupyter/
      chown -R 999:999 /data
    '';
    maxLayers = 125;
    config = {
      Cmd = [ "/bin/start-jupyenv" ];
      Env = [
        "PATH=/bin:/usr/bin"
        "LD_LIBRARY_PATH=/lib"
      ];
      WorkingDir = "/data";
      Volumes = { "/data/work" = { }; };
      ExposedPorts = {
        "8080/tcp" = {};
      };
    };
  };
in {
  submodules.imports = [
    {
      module = {
        name,
        config,
        ...
      }: let
        cfg = config.submodule.args;
      in {
        imports = with kubenix.modules; [submodule docker k8s];

        options.submodule.args = {
          namespace = mkOption {
            default = "jupyenv-${name}";
            type = types.str;
            description = "Target namespace.";
          };

          token = mkOption {
            type = types.str;
            description = "JupyterLab access token.";
          };

          storageSize = mkOption {
            type = types.str;
            default = "1Gi";
            description = "JupyterLab PV size.";
          };

          settings = mkOption {
            type = types.attrs;
            default = {
              kernel.python.example.enable = true;
            };
            description = "JupyterLab PV size.";
          };

          maxKernels = mkOption {
            type = types.int;
            default = 1;
            description = "Max JupyterLab kernels.";
          };

          package = mkOption {
            type = types.nullOr types.package;
            default = jupyenv.lib."x86_64-linux".mkJupyterlabNew cfg.settings;
            description = "Jupyter package.";
          };
        };

        config = {
          submodule = {
            name = "jupyenv";
            passthru = {
              kubernetes.objects = config.kubernetes.objects;
              docker.images = config.docker.images;
            };
          };

          kubernetes.namespace = cfg.namespace;
          kubernetes.resources.namespaces.${cfg.namespace} = { };

          kubernetes.resources.secrets."jupyenv-${name}" = {
            stringData = {
              "JUPYTER_TOKEN" = cfg.token;
            };
          };

          kubernetes.resources.persistentVolumeClaims."jupyenv-${name}" = {
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = cfg.storageSize;
            };
          };

          kubernetes.resources.services."jupyenv-${name}" = {
            spec = {
              selector.app = "jupyenv-${name}";
              ports = [{
                protocol = "TCP";
                port = 8080;
                targetPort = 8080;
              }];
            };
          };

          kubernetes.resources.deployments."jupyenv-${name}" = {
            metadata.labels.app = "jupyenv-${name}";
            spec = {
              replicas = 1;
              selector.matchLabels.app = "jupyenv-${name}";
              template = {
                metadata.labels.app = "jupyenv-${name}";
                spec = {
                  volumes = [{
                    name = "data";
                    persistentVolumeClaim.claimName = "jupyenv-${name}";
                  }];
                  containers = [{
                    name = "jupyenv";
                    resources = {
                      requests = {
                        memory = "256Mi";
                        cpu = "250m";
                      };
                      limits = {
                        memory = "1Gi";
                        cpu = "500m";
                      };
                    };
                    readinessProbe = {
                      tcpSocket.port = 8080;
                      initialDelaySeconds = 15;
                      periodSeconds = 5;
                    };
                    livenessProbe = {
                      tcpSocket.port = 8080;
                      initialDelaySeconds = 15;
                      periodSeconds = 5;
                    };
                    env = [{
                      name = "JUPYTER_TOKEN";
                      valueFrom = {
                        secretKeyRef = {
                          key = "JUPYTER_TOKEN";
                          name = "jupyenv-${name}";
                        };
                      };
                    }];
                    image = config.docker.images."jupyenv-${name}".path;
                    imagePullPolicy = "IfNotPresent";
                    ports.http.containerPort = 8080;
                    volumeMounts = [{
                      mountPath = "/data/work";
                      name = "data";
                    }];
                  }];
                };
              };
            };
          };

          docker = {
            images."jupyenv-${name}".image = buildImage cfg;
          };
        };
      };
    }
  ];
}
