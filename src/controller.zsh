#!/hint/zsh

# Copyright (c) 2026, Andrea Alberti (MIT license)

# ZLE Spinner Controller (single-process UI loop)
#
# Design:
# - Keep control inside a single ZLE widget.
# - Run the long command in a separate process.
# - Update the editor line (BUFFER/POSTDISPLAY) in a tight loop until the
#   command finishes.

_zsh_opencode_tab.run_with_spinner() {
  emulate -L zsh
  setopt localoptions localtraps no_notify extendedglob

  if [[ -z ${ZLE-} && -z ${WIDGET-} ]]; then
    return 1
  fi

  # Inputs:
  # - $1: request kind: command | persist | explain
  # - $2: original cmdline (defaults to current $BUFFER)
  local kind=${1:-command}
  local cmdline=${2:-$BUFFER}
  local -i cmd_cursor=${CURSOR:-0}

  local run_mode=${_zsh_opencode_tab[opencode.run_mode]}
  local backend_url=${_zsh_opencode_tab[opencode.backend_url]}

  # If attach mode is requested but no backend URL is configured, fall back to
  # cold mode (and warn loudly so it's not a silent behavior change).
  if [[ "$run_mode" == "attach" ]] && [[ -z $backend_url ]]; then
    zle -M "zsh-opencode-tab: attach mode requested, but Z_OC_TAB_OPENCODE_BACKEND_URL is empty (falling back to cold mode)"
    run_mode=cold
  fi

  # Prepare a short hint for error messages.
  local dbg_hint
  if (( ${_zsh_opencode_tab[debug]} )); then
    dbg_hint="see ${_zsh_opencode_tab[debug_log]}"
  else
    dbg_hint="set Z_OC_TAB_DEBUG=1 for a log"
  fi

  # Return immediately if the buffer was empty
  [[ -n $cmdline ]] || return 0

  # Note: deletion warnings are handled implicitly by the attach-mode fallback
  # above. In cold mode we delete locally and do not require a server.
  
  local _spinner_interval _spinner_render_mode _spinner_message _spinner_type
  local -a _spinner_frames

  _spinner_interval=${_zsh_opencode_tab[spinner.interval_s]}
  _spinner_message=${_zsh_opencode_tab[spinner.message]}

  # Request payload passed to the Python worker.
  #
  # - Generator flows (command/persist): pass the buffer verbatim.
  # - Explain: keep a structured payload that strips the `#?` prefix.
  local request_payload="$cmdline"
  if [[ "$kind" == "explain" ]]; then
    # Minimal parsing for explain mode only.
    # We strip the `#?` prefix from the first line and, for convenience,
    # un-comment subsequent lines if the user wrote them as `# ...`.
    local -a _lines
    _lines=("${(@f)cmdline}")

    local -a req_lines
    req_lines=()

    if (( ${#_lines} )); then
      local l0=${_lines[1]##[[:space:]]#}
      l0=${l0#\#\?}
      l0=${l0#[[:space:]]#}
      req_lines+=("$l0")
    fi

    local -i i
    for (( i = 2; i <= ${#_lines}; i++ )); do
      local l=${_lines[i]}
      local t=${l##[[:space:]]#}
      if [[ $t == \#* ]]; then
        t=${t#\#}
        t=${t#[[:space:]]#}
        req_lines+=("$t")
      else
        req_lines+=("$l")
      fi
    done

    request_payload=${(j:$'\n':)req_lines}
  fi

  # Generator contract: controller decides whether the agent should echo back
  # the user's prompt comment lines.
  local echo_prompt=0
  [[ "$kind" == "persist" ]] && echo_prompt=1

  {
    # Use a FIFO to receive the background command's exit status.
    # To avoid confusion: the FIFO contains **just** the exit status, nothing else.
    local -i status_fd
    # Capture stdout/stderr to a temp file so it doesn't corrupt ZLE.
    local out status_fifo
    {
      out="$(mktemp -t zsh-opencode-tab.out.XXXXXX)"
      status_fifo="$(mktemp -t zsh-opencode-tab.status.XXXXXX)"
      
      # Convert the temp file to FIFO
      {
        command rm -f -- "$status_fifo" 2>/dev/null
        command mkfifo -- "$status_fifo"
      }
      # Open FIFO for reading, nonblocking
      # sysopen -r -o nonblock -u status_fd "$status_fifo"
      
      # Important: opening a FIFO read-only blocks until a writer connects.
      # Open it read-write so we never hang here (macOS/BSD semantics).
      # This FIFO is opened in blocking mode on purpose so that we can later
      # use read with timeout and we do not need to handle an extra sleep cmd.
      exec {status_fd}<>"$status_fifo"
    } always {
      local ret=$?

      # Only cleanup if error
      if (( ret != 0 )); then
        command rm -f -- "$out" "$status_fifo" 2>/dev/null
        return $ret
      fi
    }

    # Run the opencode request in the background.
    #
    # Chain of delegation (from Zsh to the actual LLM worker):
    # - This ZLE widget starts a background subshell (disowned).
    # - The subshell runs a small Python wrapper: `src/opencode_generate_command.py`.
    # - The Python wrapper runs the `opencode` CLI.
    # - `opencode` runs the selected agent, which produces the final response.
    #
    # We keep the zsh side focused on ZLE rendering and process control.
    # The Python wrapper is used because it is a convenient place to:
    # - build the prompt payload (including config like GNU/MODE)
    # - parse the NDJSON stream from `opencode run --format json`
    # - optionally delete disposable sessions via the opencode server API
    #
    # In principle we could replace Python with tools like `curl` (HTTP) and
    # `jq` (JSON parsing), but that would add extra external dependencies.
    #
    # Disown the job (&!) to avoid job-control noise in interactive shells.
    # A FIFO is used to receive only the worker exit code.
    (
      emulate -L zsh
      setopt localoptions localtraps no_notify no_monitor

      # ^C was pressed
      TRAPINT() {
        print -r -- 130 >"$status_fifo" 2>/dev/null
        exit 130
      }
      # kill command was received
      TRAPTERM() {
        print -r -- 143 >"$status_fifo" 2>/dev/null
        exit 143
      }

      # Build the worker command with the current plugin configuration.
      {
        local script="${_zsh_opencode_tab[dir]}/src/opencode_generate_command.py"
        local worker_run_mode=$run_mode
        local workdir=${_zsh_opencode_tab[opencode.workdir]}

        # Ensure the bundled agents exist in the workdir.
        # We overwrite them to make plugin upgrades deterministic.
        local agents_dst="${workdir}/.opencode/agents"
        command mkdir -p -- "$agents_dst"
        command cp -f -- "${_zsh_opencode_tab[dir]}/opencode/agents/shell_cmd_generator.md" "$agents_dst/shell_cmd_generator.md"
        command cp -f -- "${_zsh_opencode_tab[dir]}/opencode/agents/shell_cmd_explainer.md" "$agents_dst/shell_cmd_explainer.md"

        # Select agent/model based on request kind.
        # - command/persist: generator
        # - explain: explainer
        local agent_to_use model_to_use
        if [[ "$kind" == "explain" ]]; then
          agent_to_use=${_zsh_opencode_tab[opencode.agent.explainer]}
          model_to_use=${_zsh_opencode_tab[opencode.model.explainer]}
        else
          agent_to_use=${_zsh_opencode_tab[opencode.agent.generator]}
          model_to_use=${_zsh_opencode_tab[opencode.model.generator]}
        fi

        local -a cmd
        cmd=(python3 "$script" \
          --user-request "$request_payload" \
          --ostype "$OSTYPE" \
          --gnu "${_zsh_opencode_tab[opencode.gnu]}" \
          --kind "$kind" \
          --echo-prompt "$echo_prompt" \
          --workdir "$workdir" \
          --backend-url "${_zsh_opencode_tab[opencode.backend_url]}" \
          --run-mode "$worker_run_mode" \
          --title "${_zsh_opencode_tab[opencode.title]}" \
          --agent "$agent_to_use"
        )

        [[ -n $model_to_use ]] && cmd+=(--model "$model_to_use")
        [[ -n ${_zsh_opencode_tab[opencode.variant]} ]] && cmd+=(--variant "${_zsh_opencode_tab[opencode.variant]}")
        [[ -n ${_zsh_opencode_tab[opencode.log_level]} ]] && cmd+=(--log-level "${_zsh_opencode_tab[opencode.log_level]}")
        (( ${_zsh_opencode_tab[opencode.print_logs]} )) && cmd+=(--print-logs)
        if (( ${_zsh_opencode_tab[opencode.delete_session]} )); then
          # Deletion strategy:
          # - attach: opencode server owns sessions; worker calls the HTTP API.
          # - cold: controller deletes local files after parsing session_id.
          [[ "$worker_run_mode" == "attach" && -n ${_zsh_opencode_tab[opencode.backend_url]} ]] && cmd+=(--delete-session)
        fi
        (( ${_zsh_opencode_tab[opencode.dummy]} )) && cmd+=(--debug-dummy)
        [[ -n ${_zsh_opencode_tab[opencode.dummy_text]} ]] && cmd+=(--debug-dummy-text "${_zsh_opencode_tab[opencode.dummy_text]}")
      }

      # Run the worker. Its stdout/stderr are captured into $out.
      "${cmd[@]}"

      local -i child_rc=$?
      print -r -- $child_rc >"$status_fifo" 2>/dev/null
      exit $child_rc
    ) >"$out" 2>&1 &!
    local -i pid=$!

    local -i cancelled=0
    local -i cancel_t0=-1 # track the elapsed time since the first TRAPINT
    local -i cancel_sent_term=0
    local -i cancel_sent_kill=0
    # Relay Ctrl-C signals to the background process
    TRAPINT() {
      cancelled=1
      (( cancel_t0 == -1 )) && cancel_t0=$SECONDS
      # Interrupt the background process; a negative PID sends
      # SIGINT to the entire process group whose PGID = $pid.
      # If that doesn't work, signal the one process.
      command kill -INT -$pid 2>/dev/null || command kill -INT $pid 2>/dev/null
    }

    # Animate the spinner while waiting for the exit code over the FIFO.
    local -i rc=1
    local line=""
    local -i frame_count=0
    local -F now next_deadline frame_s
    frame_s=$(( ${_zsh_opencode_tab[spinner.frame_ms]} / 1000.0 ))

    {
      _zsh_opencode_tab.spinner.init
      now=$EPOCHREALTIME
      next_deadline=$now

      while true; do
        # 1) Poll for completion without blocking ZLE.
        if read -t ${_zsh_opencode_tab[spinner.poll_s]} -u $status_fd line; then
          if [[ "$line" == <-> ]]; then
            rc=$line
          else
            rc=1
          fi
          break
        fi

        # 2) Escalate cancellation if needed.
        if (( cancelled )); then
          if ! command kill -0 $pid 2>/dev/null; then
            rc=1
            break
          fi
          if (( ! cancel_sent_term && (SECONDS - cancel_t0) >= 2 )); then
            command kill -TERM -$pid 2>/dev/null || command kill -TERM $pid 2>/dev/null
            cancel_sent_term=1
          fi
          if (( ! cancel_sent_kill && (SECONDS - cancel_t0) >= 4 )); then
            command kill -KILL -$pid 2>/dev/null || command kill -KILL $pid 2>/dev/null
            cancel_sent_kill=1
          fi
        fi

        # 3) Render on a fixed real-time schedule.
        now=$EPOCHREALTIME
        if (( now < next_deadline )); then
          continue
        fi
        _zsh_opencode_tab.spinner.draw_frame $frame_count
        (( frame_count++ ))
        (( next_deadline += frame_s ))
        if (( next_deadline < now )); then
          next_deadline=$(( now + frame_s ))
        fi
      done
    } always {
      _zsh_opencode_tab.spinner.cleanup
    }

  } always {
    # Close FIFO fd and remove FIFO.
    exec {status_fd}<&- 2>/dev/null
    exec {status_fd}>&- 2>/dev/null
    command rm -f -- "$status_fifo" 2>/dev/null
  }

  # If cancelled or failed, restore the original line.
  if (( cancelled )) || (( rc != 0 )); then
    BUFFER="$cmdline"
    CURSOR=$cmd_cursor
    POSTDISPLAY=""
    region_highlight=()
    zle -R
    command rm -f -- "$out" 2>/dev/null
    return $rc
  fi

  # Success: parse the python output and put the generated command into the buffer.
  local output agent_reply session_id repro_cmd rest
  output=$(<"$out")
  command rm -f -- "$out" 2>/dev/null

  # Output protocol from `src/opencode_generate_command.py`:
  # - Always: session_id + US + repro_cmd + US + agent_reply + "\n"
  # - US is ASCII Unit Separator (0x1f). It's uncommon in normal text and
  #   therefore safe as a delimiter for arbitrary multi-line shell snippets.
  # - repro_cmd is for debugging only (logged when Z_OC_TAB_DEBUG=1).
  
  # The worker may emit a trailing newline after the payload.
  # Strip exactly one final newline so delimiter checks and slicing are stable.
  output=${output%$'\n'}

  # US = ASCII Unit Separator (0x1f). We use it as a delimiter because it is
  # extremely unlikely to appear in normal shell snippets, and it allows the
  # model output to contain arbitrary newlines.
  local US=$'\x1f'

  # Strict protocol: require two delimiters.
  if [[ "$output" != *"$US"*"$US"* ]]; then
    # Fail loudly but safely: restore the user's line and show an error in the
    # ZLE message area (avoid printing to the terminal during ZLE).
    BUFFER="$cmdline"
    CURSOR=${#BUFFER}
    zle -R
    
    # Show the error in the message area.
    zle -M "zsh-opencode-tab: internal protocol error (worker output missing delimiter; $dbg_hint)"
    return 1
  fi

  # Split exactly twice:
  # - session_id: everything before first US (may be empty)
  # - repro_cmd: everything between first and second US (single line)
  # - agent_reply: everything after second US (may be multi-line)
  session_id=${output%%"$US"*}
  rest=${output#*"$US"}
  repro_cmd=${rest%%"$US"*}
  agent_reply=${rest#*"$US"}

      if (( ${_zsh_opencode_tab[debug]} )); then
        local dbg_file=${_zsh_opencode_tab[debug_log]}
        {
          print -r -- "----- zsh-opencode-tab worker -----"
          print -r -- "timestamp=$(date)"
          print -r -- "kind=$kind"
          print -r -- "workdir=${_zsh_opencode_tab[opencode.workdir]}"
          print -r -- "session_id=$session_id"
          print -r -- "repro_cmd:"
          print -r -- "$repro_cmd"
          print -r -- "agent_reply:"
          print -r -- "$agent_reply"
          print -r -- "-----"
        } >>| "$dbg_file" 2>/dev/null
      fi

  # Cold-mode session deletion: delete local files (no server needed).
  if (( ${_zsh_opencode_tab[opencode.delete_session]} )) && [[ "$run_mode" == "cold" ]] && [[ -n $session_id ]]; then
    _zsh_opencode_tab.delete_session_local "$session_id" "$dbg_hint"
  fi
  
  # Empty output means we have nothing meaningful to insert.
  if [[ -z ${agent_reply//[[:space:]]/} ]]; then
    BUFFER="$cmdline"
    CURSOR=${#BUFFER}
    zle -R

    # Show the error in the message area.
    zle -M "zsh-opencode-tab: agent communication error (agent returned an empty message; $dbg_hint)"
    return 1
  fi

  if [[ "$kind" == "persist" ]]; then
    # Persist mode: the generator agent is responsible for echoing the user's
    # prompt lines (and may add its own notes using its own conventions).
    BUFFER="$agent_reply"
  elif [[ "$kind" == "explain" ]]; then
    # Restore user prompt before printing.
    BUFFER="$cmdline"
    CURSOR=$cmd_cursor
    POSTDISPLAY=""
    region_highlight=()
    
    # Explanation mode: print the agent answer to the terminal scrollback.
    #
    # We intentionally do NOT insert explanation text into the ZLE buffer
    # (as commented lines) because it becomes hard to read.
    if [[ "$kind" == "explain" ]]; then
      # Add a separation line between the prompt and the agent answer.
      # The extra newlines at the end ensure the prompt redraw does not end up
      # on the same line and visually overwrite the last line of output.
      local explain_text=$'---\n'"$agent_reply"

      local explain_file
      explain_file="$(mktemp -t zsh-opencode-tab.explain.XXXXXX)" || return 1
      print -r -- "$explain_text" >| "$explain_file" 2>/dev/null || { command rm -f -- "$explain_file" 2>/dev/null; return 1; }

      # One-shot printer (outside ZLE).
      #
      # We cannot safely run cat/bat while ZLE is active because prompt redraws
      # (and syntax highlighting) race terminal output. Instead we register a
      # one-shot `precmd` hook that runs right before the next prompt.
      _zsh_opencode_tab.explain.precmd() {
        emulate -L zsh
        setopt localoptions

        # One-shot hook:
        # - `precmd` runs outside ZLE, right before the prompt is drawn.
        # - We unregister ourselves immediately so we do not permanently change
        #   the user's prompt behavior.
        # - The payload is passed via `_zsh_opencode_tab[explain.file]` (a temp
        #   file path written by the ZLE widget).

        autoload -Uz add-zsh-hook
        add-zsh-hook -d precmd _zsh_opencode_tab.explain.precmd 2>/dev/null

        # Read and clear the pending file path first, so failures do not leave
        # us stuck in a "pending" state.
        local f=${_zsh_opencode_tab[explain.file]}
        _zsh_opencode_tab[explain.file]=''

        if [[ -z $f || ! -r $f ]]; then
          [[ -n $f ]] && command rm -f -- "$f" 2>/dev/null
          return 0
        fi

        # Build the print command.
        # - The user configures this via `Z_OC_TAB_EXPLAIN_PRINT_CMD`.
        # - Use '{}' as an optional placeholder for the file path.
        # - If no placeholder is present, append the file path as the last arg
        #   (no '--' to keep BSD/macOS tools like `cat` compatible).
        local print_cmd=${_zsh_opencode_tab[explain.print_cmd]}
        [[ -n $print_cmd ]] || print_cmd='cat'

        local -a print_argv
        print_argv=( ${=print_cmd} )
        (( ${#print_argv} )) || print_argv=(cat)

        local -i has_placeholder=0
        local -i i
        for (( i = 1; i <= ${#print_argv}; i++ )); do
          if [[ ${print_argv[i]} == *'{}'* ]]; then
            has_placeholder=1
            print_argv[i]=${print_argv[i]//\{\}/$f}
          fi
        done
        if (( ! has_placeholder )); then
          print_argv+=("$f")
        fi

        local -i rc=0
        {
          if [[ ${print_argv[1]} == command ]]; then
            "${print_argv[@]}"
          else
            command "${print_argv[@]}"
          fi
          rc=$?
        } always {
          command rm -f -- "$f" 2>/dev/null
        }
        return $rc
      }

      # Inside ZLE widget (explain mode): schedule printing, then consume
      # the line as a comment (no-op) to return a fresh prompt.
      _zsh_opencode_tab[explain.file]="$explain_file"
      autoload -Uz add-zsh-hook
      add-zsh-hook -d precmd _zsh_opencode_tab.explain.precmd 2>/dev/null
      add-zsh-hook precmd _zsh_opencode_tab.explain.precmd
      BUFFER="$cmdline"
      CURSOR=${#BUFFER}
      zle accept-line

      return 0
    fi
    return 0
  else
    # Command mode: put the generated command(s) into the buffer. The user can
    # edit and run them by pressing Enter.
    BUFFER="$agent_reply"
  fi
  # Place the cursor at the end of the inserted reply.
  CURSOR=${#BUFFER}
  zle -R
  return 0
}

_zsh_opencode_tab.delete_session_local() {
  emulate -L zsh
  setopt localoptions extendedglob

  local session_id=${1:-}
  local dbg_hint=${2:-}

  session_id=${session_id##[[:space:]]#}
  session_id=${session_id%%[[:space:]]#}

  # Basic sanity guard: avoid path injection.
  if [[ -z $session_id || $session_id != ses_* || $session_id == */* ]]; then
    zle -M "zsh-opencode-tab: cold delete failed (invalid session id: ${session_id:-<empty>})"
    return 1
  fi

  local data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
  local root="$data_home/opencode/storage"
  local session_file="$root/session/global/$session_id.json"

  if [[ ! -f $session_file ]]; then
    local msg="zsh-opencode-tab: cold delete failed (cannot find session file for $session_id)"
    [[ -n $dbg_hint ]] && msg+="; $dbg_hint"
    zle -M "$msg"
    return 1
  fi

  command rm -rf -- "$root/message/$session_id" 2>/dev/null
  command rm -f -- "$session_file" 2>/dev/null
  command rm -f -- "$root/session_diff/$session_id.json" 2>/dev/null

  # Other possible session artifacts (intentionally not deleted because
  # they are normally not produced for a single-shot prompt):
  # - "$root/part/msg_<id>/..." (parts keyed by message id, not session id)
  # - "$root/project/..." (project metadata)
  # We keep deletion conservative until we fully understand opencode's storage.

  command rm -f -- "$root/session_share/$session_id.json" 2>/dev/null
  command rm -f -- "$root/todo/$session_id.json" 2>/dev/null

  return 0
}

# Backwards-compatible wrapper.
_zsh_opencode_tab_run_with_spinner() {
  _zsh_opencode_tab.run_with_spinner "$@"
}
