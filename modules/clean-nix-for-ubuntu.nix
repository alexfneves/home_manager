{ pkgs, lib, hostConfig, ... }:

{
  programs.zsh = lib.mkIf (hostConfig.enableCleanNixEnv or false) {
    initContent = lib.mkAfter ''
clean-nix-for-ubuntu() {
  export LD_LIBRARY_PATH=""
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:/home/afn/.zsh/plugins/fast-syntax-highlighting:/home/afn/.zsh/plugins/zsh-autocomplete"
  unset LIBGL_DRIVERS_PATH
  unset LIBVA_DRIVERS_PATH
  unset LOCALE_ARCHIVE_2_27
  unset __EGL_VENDOR_LIBRARY_FILENAMES
  unset XCURSOR_PATH
  unset XDG_DATA_DIRS
  unset NIX_PROFILES
  unset NIX_SSL_CERT_FILE
}

alias c='clean-nix-for-ubuntu'
'';
  };
}
