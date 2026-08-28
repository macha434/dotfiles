#!/bin/bash
# Claude Code status line, converted from the zsh prompt defined in ~/.zshrc:
#   PROMPT='%1~$(git_branch_prompt) %# '
# Shows the current directory's last path segment (~ for $HOME) followed by
# " (branch)" when inside a git repository.

input=$(cat)
dir=$(echo "$input" | jq -r '.workspace.current_dir')

# Mimic zsh's %1~ : last path component, with $HOME shown as "~".
if [ "$dir" = "$HOME" ]; then
  display_dir="~"
else
  display_dir=$(basename "$dir")
fi

branch=""
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --quiet --short HEAD 2>/dev/null) \
    || branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

if [ -n "$branch" ]; then
  printf '%s (%s)' "$display_dir" "$branch"
else
  printf '%s' "$display_dir"
fi
