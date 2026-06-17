# Determinate Nix Installer places its profile script under
# /nix/var/nix/profiles/default; legacy installs use ~/.nix-profile.
for nix_profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish \
    "$HOME/.nix-profile/etc/profile.d/nix.fish"
    if test -e "$nix_profile"
        source "$nix_profile"
        break
    end
end
