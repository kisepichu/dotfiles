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

# Fallback: ensure the per-user nix profile bin is on PATH even if the profile
# script above was missing or did not export it (e.g. on some managed setups).
if test -d "$HOME/.nix-profile/bin"; and not contains -- "$HOME/.nix-profile/bin" $PATH
    set -gx PATH "$HOME/.nix-profile/bin" $PATH
end
