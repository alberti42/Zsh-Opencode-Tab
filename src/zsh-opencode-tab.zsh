#!/hint/zsh

# Copyright (c) 2026, Andrea Alberti (MIT license)

# Compile and load modules
() {
  local -A modules=(
    "zsh-opencode-tab.plugin.zsh" 0 # we skip loading this module since it is already loaded
    "src/controller.zsh"          1
    "src/spinner.zsh"             1
  )

  local module flag script compiled_script

  for module in ${(k)modules}; do
    flag=$modules[$module]

    script="${_zsh_opencode_tab[dir]}/$module"
    compiled_script="${script}.zwc"

    # Always compile (only if missing or out of date)
    if [[ ! -f "$compiled_script" || "$script" -nt "$compiled_script" ]]; then
      zcompile -Uz -- "$script" "$compiled_script"
    fi

    # Only load when enabled
    (( flag )) && builtin source "$script"
  done
}

# Hook function responding to the configured trigger key (default: TAB)
function _zsh_opencode_tab_or_fallback() {
  # Do not add anything that changes zsh options like `emulate -LR zsh`
  # This will certainly break other widgets that are called as
  # a fallback case when our widget delegates other to act upon the TAB
  # keypress event. This would break plugins like `Aloxaf/fzf-tab`.
  # So we keep on purpose the logic of `_zsh_opencode_tab_or_fallback`
  # very simple and short, without relying on special zsh options.
  
  # NOTE: the regex is quoted so `#` is not parsed as a shell comment.
  if [[ $BUFFER =~ '^[[:space:]]*#\?' ]]; then
    _zsh_opencode_tab.run_with_spinner explain "$BUFFER"
  elif [[ $BUFFER =~ '^[[:space:]]*#\+' ]]; then
    # Force persistence regardless of global default.
    _zsh_opencode_tab.run_with_spinner persist "$BUFFER"
  elif [[ $BUFFER =~ '^[[:space:]]*#-' ]]; then
    # Force non-persistence regardless of global default.
    _zsh_opencode_tab.run_with_spinner command "$BUFFER"
  elif [[ $BUFFER =~ '^[[:space:]]*#' ]]; then
    # Plain '#': follow the configured default.
    if (( ${_zsh_opencode_tab[persist.default]} )); then
      _zsh_opencode_tab.run_with_spinner persist "$BUFFER"
    else
      _zsh_opencode_tab.run_with_spinner command "$BUFFER"
    fi
  else
    # Fallback to whatever was originally bound to the trigger key in the current keymap.
    # Note: $KEYMAP is often "main" (not "emacs"/"viins").
    local km="${KEYMAP:-main}"
    local orig_widget="${_zsh_opencode_tab[orig_widget_$km]}"
    if [[ -z "$orig_widget" && "$km" != "main" ]]; then
      # If orig was empty, but $KEYMAP was not main,
      # then try again with main
      orig_widget="${_zsh_opencode_tab[orig_widget_main]}"
    fi

    if [[ -n "$orig_widget" && "$orig_widget" != "_zsh_opencode_tab_or_fallback" ]]; then
      # Call the original widget bound to the trigger key
      zle "$orig_widget"
    else
      zle expand-or-complete
    fi
  fi
}
