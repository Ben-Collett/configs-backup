set -q GHCUP_INSTALL_BASE_PREFIX[1]; or set GHCUP_INSTALL_BASE_PREFIX $HOME
set -gx PATH $HOME/.cabal/bin /home/ben/.ghcup/bin $PATH # ghcup-env
# opencode
fish_add_path /home/ben/.opencode/bin
if status is-interactive
    # @fish-lsp-disable-next-line 2003
    set -U fish_greeting

    # Commands to run in interactive sessions can go here
    source ~/.config/fish/easy_env.fish
    source ~/.config/fish/keybindings.fish
    source ~/.config/fish_secrets.fish

    zoxide init fish | source

    set -g __session_has_run 0

    function __mark_session_active --on-event fish_preexec
        set -g __session_has_run 1
    end
end

# Added by LM Studio CLI (lms)
set -gx PATH $PATH /home/ben/.lmstudio/bin
# End of LM Studio CLI section

