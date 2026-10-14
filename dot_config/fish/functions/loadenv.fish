function loadenv --description 'Export variables from a bash-style env file (default: .env) into the current fish session'
    set -l file .env
    if set -q argv[1]
        set file $argv[1]
    end

    if not test -f "$file"
        echo "loadenv: $file: no such file" >&2
        return 1
    end

    if not functions -q bass
        echo "loadenv: bass is not installed; run 'fisher update'" >&2
        return 1
    end

    # bass only carries back exported variables, and .env files rarely use
    # `export`, so `bass source .env` alone is a silent no-op. `set -a`
    # auto-exports every assignment the file makes.
    set -l quoted (string replace --all "'" "'\\''" -- "$file")
    bass "set -a; source '$quoted'"
end
