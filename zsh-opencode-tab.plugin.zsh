#!/hint/zsh

# Copyright (c) 2026, Andrea Alberti (MIT license)

# Dynamically load '_zsh_opencode_tab' function by overwriting
# the loader function below with the actual function the first
# time this function is invoked. This prevents keeps loading the
# plugin on the logon fast, the defer the actual loading to later
# when the plugin is used
function _zsh_opencode_tab_or_fallback() {
  # Do not add anything that changes zsh options like `emulate -LR zsh`
  # This will certainly break other widgets that are called as
  # a fallback case when our widget delegates other to act upon the TAB
  # keypress event. This would break plugins like `Aloxaf/fzf-tab`.
  # So we keep on purpose the logic of `_zsh_opencode_tab_or_fallback`
  # very simple and short, without relying on special zsh options.
  
  local loader_path="${${(%):-%x}:a:h}"

  # Determine the directory of the loader and append the script path
  local script="${loader_path}/src/zsh-opencode-tab.zsh"

  # Load the actual script; it shadows/overwrites this loader
  builtin source "$script"

  # We call the actual function
  _zsh_opencode_tab_or_fallback "$@"
}

# Test compatibility with the current shell
() {
  autoload -Uz is-at-least
  if ! is-at-least 5.1; then
    # EPOCHREALTIME is first introduced with zsh 5.1
    print -u2 -- "zsh-opencode-tab requires zsh with EPOCHREALTIME (zsh >= 5.1)."
    return 1
  fi
}

# Create a keymap to organize the variables of this zsh plugin
typeset -gA _zsh_opencode_tab

# Absolute directory of this plugin file
_zsh_opencode_tab[dir]="${${(%):-%x}:a:h}"
_zsh_opencode_tab[debug]=${Z_OC_TAB_DEBUG:-"0"}
_zsh_opencode_tab[debug_log]=${Z_OC_TAB_DEBUG_LOG:-'/tmp/zsh-opencode-tab.log'}
_zsh_opencode_tab[explain.print_cmd]=${Z_OC_TAB_EXPLAIN_PRINT_CMD:-'cat'}
_zsh_opencode_tab[explain.file]=''

# Trigger key for this plugin (bindkey notation).
# Default is TAB (^I). If you want to avoid conflicts with other completion
# plugins that re-bind TAB (e.g. fzf-tab), set Z_OC_TAB_BINDKEY to another key
# sequence like '^G'.
_zsh_opencode_tab[bindkey.key]=${Z_OC_TAB_BINDKEY:-'^I'}

# Default behavior for plain `# <request><TAB>`.
# - 1: persist (keep the request line as a comment above the generated command)
# - 0: non-persist (replace the buffer with the generated command)
_zsh_opencode_tab[persist.default]=${Z_OC_TAB_PERSIST_DEFAULT:-1}

# Spinner configuration (resolved once at plugin load time)
() {
  emulate -L zsh

  # Defaults matching spinner.ts (opencode)
  _zsh_opencode_tab[spinner.padL]=30
  _zsh_opencode_tab[spinner.padR]=9
  _zsh_opencode_tab[spinner.viewLen]=8
  _zsh_opencode_tab[spinner.trailLen]=6

  # Text (rendered via ZLE/region_highlight)
  _zsh_opencode_tab[spinner.dot_char]='.'
  _zsh_opencode_tab[spinner.train_char]='■'
  _zsh_opencode_tab[spinner.message]=${Z_OC_TAB_SPINNER_MESSAGE:-'AI agent is busy ...'}
  _zsh_opencode_tab[spinner.message_fg]=${Z_OC_TAB_SPINNER_MESSAGE_FG:-''}

  # Base color for the effect is configured in HSV.
  # The trail palette is derived from this single bright color.
  _zsh_opencode_tab[spinner.hue]=${Z_OC_TAB_SPINNER_HUE:-280}
  _zsh_opencode_tab[spinner.saturation]=${Z_OC_TAB_SPINNER_SATURATION:-0.30}
  _zsh_opencode_tab[spinner.value]=${Z_OC_TAB_SPINNER_VALUE:-1.0}

  # Inactive dots are a dimmed version of the base color.
  # In upstream code this is alpha (opacity). In terminals we simulate alpha by
  # blending with a configured background.
  _zsh_opencode_tab[spinner.inactive_factor]=${Z_OC_TAB_SPINNER_INACTIVE_FACTOR:-0.4}

  # Global fading for inactive dots (like opencode):
  # - during movement: fade in from minAlpha to 1
  # - during holds: fade out from 1 to minAlpha
  _zsh_opencode_tab[spinner.enable_fading]=${Z_OC_TAB_SPINNER_ENABLE_FADING:-1}
  _zsh_opencode_tab[spinner.min_alpha]=${Z_OC_TAB_SPINNER_MIN_ALPHA:-0.0}

  # Background color used for alpha blending and as the bar's background.
  # Leave empty for transparent background (works with any terminal theme).
  # Set to a hex color (e.g., '#24273A') if you want a solid background.
  _zsh_opencode_tab[spinner.bg_hex]=${Z_OC_TAB_SPINNER_BG_HEX:-''}

  # Timing
  # The single speed knob is the frame interval (seconds per frame).
  _zsh_opencode_tab[spinner.interval_s]=${Z_OC_TAB_SPINNER_INTERVAL:-0.03}
  local -F interval_s=${_zsh_opencode_tab[spinner.interval_s]}
  local -i frame_ms=$(( interval_s * 1000.0 + 0.5 ))
  (( frame_ms < 1 )) && frame_ms=1
  _zsh_opencode_tab[spinner.frame_ms]=$frame_ms

  # Poll timeout for FIFO reads (seconds).
  # Lower values react quicker but can burn more CPU.
  _zsh_opencode_tab[spinner.poll_s]=${Z_OC_TAB_SPINNER_POLL_S:-0.005}
}

# Opencode integration (resolved once at plugin load time)
() {
  emulate -L zsh

  # Backend server URL (optional): used for session deletion and attach-mode runs.
  _zsh_opencode_tab[opencode.backend_url]=${Z_OC_TAB_OPENCODE_BACKEND_URL:-''}

  # Working directory for the `opencode` subprocess.
  # We default to a temp directory so opencode sessions are created in the global
  # workspace (not project-scoped when the user happens to be inside a git repo).
  local default_workdir
  if [[ -n ${XDG_DATA_HOME:-} ]]; then
    default_workdir="${XDG_DATA_HOME}/zsh-opencode-tab"
  else
    default_workdir="${TMPDIR:-/tmp}/zsh-opencode-tab"
  fi
  _zsh_opencode_tab[opencode.workdir]="${Z_OC_TAB_OPENCODE_WORKDIR:-$default_workdir}"

  # How to run opencode:
  # - cold (default): run `opencode run ...` (no server attach)
  # - attach: run `opencode run --attach <backend_url> ...`
  _zsh_opencode_tab[opencode.run_mode]=${Z_OC_TAB_OPENCODE_RUN_MODE:-'cold'}

  # Optional. Format: provider/model
  #
  # Model selection supports a shared default plus per-mode overrides:
  # - Z_OC_TAB_OPENCODE_MODEL: sets both generator + explainer
  # - Z_OC_TAB_OPENCODE_MODEL_GENERATOR: overrides generator only
  # - Z_OC_TAB_OPENCODE_MODEL_EXPLAINER: overrides explainer only
  _zsh_opencode_tab[opencode.model]=${Z_OC_TAB_OPENCODE_MODEL:-''}
  _zsh_opencode_tab[opencode.model.generator]=${Z_OC_TAB_OPENCODE_MODEL:-''}
  _zsh_opencode_tab[opencode.model.explainer]=${Z_OC_TAB_OPENCODE_MODEL:-''}
  [[ -n ${Z_OC_TAB_OPENCODE_MODEL_GENERATOR:-''} ]] && _zsh_opencode_tab[opencode.model.generator]=${Z_OC_TAB_OPENCODE_MODEL_GENERATOR}
  [[ -n ${Z_OC_TAB_OPENCODE_MODEL_EXPLAINER:-''} ]] && _zsh_opencode_tab[opencode.model.explainer]=${Z_OC_TAB_OPENCODE_MODEL_EXPLAINER}

  # Agent selection: generator and explainer are distinct agents.
  # In cold mode, this plugin ensures its bundled agents exist in:
  #   ${Z_OC_TAB_OPENCODE_WORKDIR:-$default_workdir}/.opencode/agents/
  _zsh_opencode_tab[opencode.agent.generator]=${Z_OC_TAB_OPENCODE_AGENT_GENERATOR:-'shell_cmd_generator'}
  _zsh_opencode_tab[opencode.agent.explainer]=${Z_OC_TAB_OPENCODE_AGENT_EXPLAINER:-'shell_cmd_explainer'}
  _zsh_opencode_tab[opencode.variant]=${Z_OC_TAB_OPENCODE_VARIANT:-''}

  # "GNU" is passed as opaque config to the agent (no validation/clamping here).
  # Valid values are conventionally 0/1, but we trust user configuration.
  _zsh_opencode_tab[opencode.gnu]=${Z_OC_TAB_OPENCODE_GNU:-1}

  # Set a fixed title to avoid title-generation overhead.
  _zsh_opencode_tab[opencode.title]=${Z_OC_TAB_OPENCODE_TITLE:-'zsh shell assistant'}

  # Logging (useful for debugging opencode issues)
  _zsh_opencode_tab[opencode.log_level]=${Z_OC_TAB_OPENCODE_LOG_LEVEL:-''}
  _zsh_opencode_tab[opencode.print_logs]=${Z_OC_TAB_OPENCODE_PRINT_LOGS:-0}

  # Disposable sessions: delete the created session after we got the answer.
  _zsh_opencode_tab[opencode.delete_session]=${Z_OC_TAB_OPENCODE_DELETE_SESSION:-1}

  # Debug: bypass opencode and return a dummy reply (fast UI iteration).
  _zsh_opencode_tab[opencode.dummy]=${Z_OC_TAB_OPENCODE_DUMMY:-0}
  _zsh_opencode_tab[opencode.dummy_text]=${Z_OC_TAB_OPENCODE_DUMMY_TEXT:-''}
}

# Saves original binding per keymap; binds trigger key to _zsh_opencode_tab_or_fallback.
# We don't assume any specific completion plugin; we preserve whatever was bound.
(){
  local keymap keymaps binding orig_widget bindkey_key
  bindkey_key="${_zsh_opencode_tab[bindkey.key]}"
  if [[ -z "$bindkey_key" ]]; then
    bindkey_key='^I'
    _zsh_opencode_tab[bindkey.key]="$bindkey_key"
  fi
  
  local -a keymaps=(main emacs viins vicmd visual)

  # First pass: snapshot what is currently bound.
  # This must happen before we bind anything, because some keymaps can share
  # underlying bindings (so changing one can affect others).
  for keymap in $keymaps; do
    binding=$(bindkey -M "$keymap" "$bindkey_key" 2>/dev/null) || binding=""
    orig_widget="${binding##* }"
    if [[ -n "$binding" && -n "$orig_widget" && "$orig_widget" != "$bindkey_key" && "$orig_widget" != "_zsh_opencode_tab_or_fallback" ]]; then
      _zsh_opencode_tab[orig_widget_$keymap]="$orig_widget"
    fi
  done

  # Second pass: bind the trigger key in all common keymaps.
  for keymap in $keymaps; do
    bindkey -M $keymap "$bindkey_key" _zsh_opencode_tab_or_fallback
  done
}

# Register the widget
zle -N _zsh_opencode_tab_or_fallback
