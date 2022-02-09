{ pkgs, ... }: {
  home-manager.sharedModules = [
    {
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
    }
  ];
  environment.systemPackages = with pkgs; [
    # dev software
    sshuttle
    nodejs

    # AWS
    awscli2
    eksctl

    (pkgs.writeShellApplication {
      name = "tf-fmt";
      runtimeInputs = with pkgs; [ pkgs.gnugrep pkgs.gnused pkgs.coreutils pkgs.findutils ];
      text = ''
      since_revision="$1"
      cd "$(git rev-parse --show-toplevel)"

      if command -v terraform ; then
        git diff --name-only "$since_revision" | grep -E '.(tf|tfvars)$' | sed 's#/[^/]*$##g' | sort | uniq \
          | xargs -n1 -r terraform fmt
      else
        echo 'terraform executable is missing, skipping...'
      fi

      if command -v terragrunt ; then
        git diff --name-only "$since_revision" | grep -E '.(hcl)$' \
          | xargs -n1 -r terragrunt hclfmt --terragrunt-hclfmt-file
      else
        echo 'terragrunt executable is missing, skipping...'
      fi
      '';
    })
  ];
}