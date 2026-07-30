#!/usr/bin/env bash
# Deploys agent skills, subagents and commands from every repo under the parent
# directory into each harness directory.
#
# Source of truth is the set of sibling repos next to this script:
#
#     ~/.agents/
#       private/   skills/ agents/ commands/
#       public/    skills/ agents/ commands/
#       deploy.sh  (this file, shipped in each repo)
#
# Targets (~/.claude) are disposable build output. Nothing is linked;
# everything is copied. Deleting a target destroys nothing.
#
# Usage: ./deploy.sh [--check] [target ...]
set -euo pipefail

COMPONENTS=(skills agents commands)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK=0
TARGETS=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        *) TARGETS+=("$arg") ;;
    esac
done
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("$HOME/.claude")

# Symlinks are why the originals got deleted. Never recurse through one:
# unlink it and leave whatever it pointed at alone.
remove_entry() {
    local path="$1"
    if [ -L "$path" ]; then rm -f "$path"; else rm -rf "$path"; fi
}

# A harness dir nested under $ROOT would otherwise be discovered as a source
# repo and deploy its own output back over itself.
is_target() {
    local candidate="$1" t
    for t in "${TARGETS[@]}"; do
        [ "$(cd "$candidate" 2>/dev/null && pwd -P)" = "$(cd "$t" 2>/dev/null && pwd -P)" ] && return 0
    done
    return 1
}

repos=()
for dir in "$ROOT"/*/; do
    [ -d "$dir" ] || continue
    is_target "${dir%/}" && continue
    for component in "${COMPONENTS[@]}"; do
        if [ -d "${dir}${component}" ]; then repos+=("${dir%/}"); break; fi
    done
done

if [ ${#repos[@]} -eq 0 ]; then
    echo "No source repos found under $ROOT. Expected sibling directories containing skills/, agents/ or commands/." >&2
    exit 1
fi

echo "Source repos: $(for r in "${repos[@]}"; do printf '%s ' "$(basename "$r")"; done)"

# Build "<component>/<name>" -> source path, refusing to guess on collisions.
declare -A SRC REPO_OF
collisions=""
for component in "${COMPONENTS[@]}"; do
    for repo in "${repos[@]}"; do
        [ -d "$repo/$component" ] || continue
        for entry in "$repo/$component"/*; do
            [ -e "$entry" ] || continue
            key="$component/$(basename "$entry")"
            if [ -n "${SRC[$key]:-}" ]; then
                collisions+="  $key: in both '${REPO_OF[$key]}' and '$(basename "$repo")'"$'\n'
            else
                SRC[$key]="$entry"
                REPO_OF[$key]="$(basename "$repo")"
            fi
        done
    done
done

if [ -n "$collisions" ]; then
    printf 'Name collisions between repos - resolve before deploying:\n%s' "$collisions" >&2
    exit 1
fi

drift=0
for harness in "${TARGETS[@]}"; do
    echo
    echo "Target: $harness"
    for component in "${COMPONENTS[@]}"; do
        names=()
        for key in "${!SRC[@]}"; do
            [ "${key%%/*}" = "$component" ] && names+=("${key#*/}")
        done
        [ ${#names[@]} -eq 0 ] && continue

        dest="$harness/$component"

        # A symlink here is the old broken layout. Replace it with a real directory.
        if [ -L "$dest" ]; then
            echo "  $component/ is a link -> replacing with a real directory"
            drift=$((drift + 1))
            [ $CHECK -eq 0 ] && { rm -f "$dest"; mkdir -p "$dest"; }
        elif [ ! -d "$dest" ]; then
            drift=$((drift + 1))
            [ $CHECK -eq 0 ] && mkdir -p "$dest"
        fi

        for name in "${names[@]}"; do
            if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
                [ $CHECK -eq 0 ] && remove_entry "$dest/$name"
            else
                echo "  + $component/$name  (${REPO_OF[$component/$name]})"
                drift=$((drift + 1))
            fi
            [ $CHECK -eq 0 ] && cp -R "${SRC[$component/$name]}" "$dest/$name"
        done

        # Anything in the target that no source repo provides is stale output.
        # A still-linked target points at something that is not our output, so
        # skip it entirely - only the link itself gets removed.
        { [ -d "$dest" ] && [ ! -L "$dest" ]; } || continue
        for entry in "$dest"/*; do
            [ -e "$entry" ] || [ -L "$entry" ] || continue
            name="$(basename "$entry")"
            if [ -z "${SRC[$component/$name]:-}" ]; then
                echo "  - $component/$name  (not in any source repo)"
                drift=$((drift + 1))
                [ $CHECK -eq 0 ] && remove_entry "$entry"
            fi
        done
    done
done

echo
if [ $CHECK -eq 1 ]; then
    if [ $drift -eq 0 ]; then echo "In sync."; exit 0; else echo "$drift difference(s). Run ./deploy.sh to apply."; exit 1; fi
fi
echo "Deployed."
