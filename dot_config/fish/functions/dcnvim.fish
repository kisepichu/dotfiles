function dcnvim --description 'Open Neovim inside the dev container of the current directory'
    devcontainer exec --workspace-folder . nvim $argv
end
