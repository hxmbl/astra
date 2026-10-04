# home/common.nix — the shell, for machines with or without a screen.
{ config, lib, pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    history = {
      size = 50000;
      ignoreDups = true;
      share = true;
    };
    initExtra = ''
      # astra: `less` that does not eat scrollback like a pager that has
      # forgotten what a terminal is.
      export LESS='-R -F -X'
    '';
    shellAliases = {
      ls = "eza --long";
      la = "eza --long --all";
      lt = "eza --tree --level=2";
      p1 = "ping -c1 1.1.1.1";
      speed = "speedtest";
      speed-bytes = "speedtest --simple";
      clock = "tty-clock -csbt";
      tty-clock = "tty-clock -csbt";
      where = "which";
      py = "python3";
      ff = "fastfetch";
      # activate a python venv in the current directory
      source-pyvenv = "source .venv/bin/activate";
      # astra: nix flake helpers
      astra = "nix run github:hxmbl/astra#astra-info";
      astra-health = "sudo astra-boot status";
      astra-rollback = "sudo astra-boot rollback";
      quit = "exit";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      character.success_symbol = "[❯](bold green)";
      character.error_symbol = "[❯](bold red)";
      directory.truncation_length = 3;
      git_branch.symbol = " ";
      git_status = {
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        modified = "!";
        staged = "+";
        untracked = "?";
      };
      cmd_duration = {
        min_time = 2000;
        format = "took [\${duration}](bold yellow) ";
      };
      nodejs.symbol = " ";
      python.symbol = " ";
      rust.symbol = " ";
      docker_context.symbol = " ";
      golang.symbol = " ";
    };
  };

  programs.git = {
    enable = true;
    # Set these once in ~/.gitconfig-as-user or uncomment below; home-manager
    # writes ~/.gitconfig, so anything you put in your home dir by hand is
    # silently ignored. That has bitten everyone exactly once.
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      diff.algorithm = "histogram";
      merge.conflictstyle = "zdiff3";
      rerere.enabled = true;
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag.sort = "-version:refname";
      # NOTE: no `safe.directory = *` here on purpose. It disables a real
      # protection against running git config/hooks out of a directory someone
      # else wrote. If you need it, add it for the specific path.
    };
  };

  programs.tmux = {
    enable = true;
    # Not `options = [ ... ]`: home-manager has no such key. These are the
    # typed options (home-manager/modules/programs/tmux.nix): historyLimit is
    # ints.positive (line 223), focusEvents is bool (213), baseIndex is
    # ints.unsigned (163), keyMode is an enum (230), prefix is nullOr str (276).
    mouse = true;
    baseIndex = 1;
    keyMode = "vi";
    prefix = "C-a";
    historyLimit = 50000;
    escapeTime = 0;
    focusEvents = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Nothing here needs to be on PATH that the system profile does not already
  # provide; keeping home.packages empty is intentional.
  home.packages = [ ];
}