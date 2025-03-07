{
  __nixpkgs__,
  __toModuleOutputs__,
  attrsMerge,
  attrsOptional,
  escapeShellArgs,
  toBashArray,
  toBashMap,
  toFileYaml,
  makeScript,
  outputs,
  ...
}: {
  config,
  lib,
  ...
}: let
  toJobName = output: args:
    builtins.concatStringsSep "__" ([output] ++ args);

  jobType = lib.types.submodule (_: {
    options = {
      args = lib.mkOption {
        default = [];
        type = lib.types.listOf lib.types.str;
      };
      gitDepth = lib.mkOption {
        default = 1;
        type = lib.types.int;
      };
      gitlabExtra = lib.mkOption {
        default = {};
        type = lib.types.attrsOf lib.types.anything;
      };
      output = lib.mkOption {
        type = lib.types.str;
      };
    };
  });

  pipelineType = lib.types.submodule (_: {
    options = {
      gitlabPath = lib.mkOption {
        default = null;
        type = lib.types.nullOr lib.types.str;
      };
      jobs = lib.mkOption {
        default = {};
        type = lib.types.listOf jobType;
      };
    };
  });

  makeJob = {
    output,
    args,
    ...
  }: let
    name = toJobName output args;
  in {
    inherit name;
    value = makeScript {
      replace = {
        __argArgs__ = toBashArray args;
        __argOutput__ = outputs.${output};
      };
      name = "job-for-${name}";
      entrypoint = ./entrypoint-for-job.sh;
    };
  };

  makePipeline = name: {jobs, ...}: {
    name = "/pipeline/${name}";
    value = makeScript {
      entrypoint = ./entrypoint-for-pipeline.sh;
      replace = {
        __argJobs__ =
          toBashMap
          (builtins.listToAttrs (builtins.map makeJob jobs));
      };
      name = "pipeline-for-${name}";
    };
  };

  makeGitlabJob = {
    args,
    gitDepth,
    gitlabExtra,
    output,
    ...
  }: {
    name = toJobName output args;
    value = attrsMerge [
      {
        image = "ghcr.io/fluidattacks/makes:22.11";
        interruptible = true;
        needs = [];
        script =
          if args == []
          then ["m . ${output}"]
          else ["m . ${output} ${escapeShellArgs args}"];
        variables = {
          GIT_DEPTH = gitDepth;
          MAKES_GIT_DEPTH = gitDepth;
        };
      }
      gitlabExtra
    ];
  };
  makeGitlab = name: {
    gitlabPath,
    jobs,
    ...
  }: (attrsOptional
    (gitlabPath != null)
    {
      name = "/pipelineOnGitlab/${name}";
      value = makeScript {
        name = "pipeline-on-gitlab-for-${name}";
        replace = {
          __argGitlabCiYaml__ =
            toFileYaml "gitlab-ci.yaml"
            (builtins.listToAttrs
              (builtins.map makeGitlabJob jobs));
          __argGitlabPath__ = "." + gitlabPath;
        };
        searchPaths.bin = [__nixpkgs__.git];
        entrypoint = ./entrypoint-for-pipeline-on-gitlab.sh;
      };
    });
in {
  options = {
    pipelines = lib.mkOption {
      default = {};
      type = lib.types.attrsOf pipelineType;
    };
  };
  config = {
    outputs = attrsMerge [
      (__toModuleOutputs__ makePipeline config.pipelines)
      (__toModuleOutputs__ makeGitlab config.pipelines)
    ];
  };
}
