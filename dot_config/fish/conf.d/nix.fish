set -l nix_profile "$HOME/.nix-profile/etc/profile.d/nix.fish"
if test -e "$nix_profile"
    source "$nix_profile"
end
