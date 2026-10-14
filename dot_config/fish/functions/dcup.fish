function dcup --description 'devcontainer up for the current directory, with Neovim from these dotfiles'
    set -l repository https://github.com/kisepichu/dotfiles.git
    # Override to try unmerged changes, e.g. a path the project mounts into the container.
    if set -q DCUP_DOTFILES_REPOSITORY
        set repository $DCUP_DOTFILES_REPOSITORY
    end

    # The CLI installs dotfiles once per container; pass --remove-existing-container to pick up updates.
    devcontainer up --workspace-folder . \
        --dotfiles-repository $repository \
        --dotfiles-install-command scripts/install-devcontainer-neovim.sh $argv
end
