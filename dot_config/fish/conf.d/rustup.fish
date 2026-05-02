set -l cargo_env "$HOME/.cargo/env.fish"
if test -e "$cargo_env"
    source "$cargo_env"
end
