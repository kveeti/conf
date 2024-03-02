{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  nixpkgs = {
    overlays = [
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  home = {
    username = "kveeti";
    homeDirectory = "/home/kveeti";

    file."./.config/nvim/" = {
      source = ./nvim2;
      recursive = true;
    };

    file."./.config/tmux/" = {
      source = ./tmux;
      recursive = true;
    };
  };

  systemd.user.startServices = "sd-switch";

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs; [
      vimPlugins.telescope-nvim
      vimPlugins.plenary-nvim
      vimPlugins.copilot-lua
      vimPlugins.nvim-treesitter.withAllGrammars
      vimPlugins.nvim-treesitter-context
      vimPlugins.fidget-nvim
      vimPlugins.monokai-pro-nvim
      vimPlugins.cmp-nvim-lsp
      vimPlugins.nvim-cmp
      vimPlugins.cmp-path
      vimPlugins.luasnip
      vimPlugins.cmp_luasnip
      vimPlugins.nvim-ts-autotag
      vimPlugins.nvim-autopairs

      # languages
      lua-language-server
      vimPlugins.nvim-lspconfig
      vimPlugins.rust-tools-nvim
      rust-analyzer
      nodePackages.typescript-language-server
      nodePackages.typescript
      nodePackages.yaml-language-server
      gopls

      # formatters
      alejandra
      gofumpt
      golines
      rustfmt
    ];
  };

  home.stateVersion = "23.11";
}
