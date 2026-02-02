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

  # Don't let the user's tracing options corrupt the prompt while ZLE is active.
  # (e.g. `set -x` / `setopt xtrace` can print variable assignments like `line=0`.)
  unsetopt xtrace verbose 2>/dev/null || true

  if [[ -z ${ZLE-} && -z ${WIDGET-} ]]; then
    return 1
  fi

  # Inputs:
  # - $1: request kind: command | keep | explain
  # - $2: original cmdline (defaults to current $BUFFER)
  local kind=${1:-command}
  local cmdline=${2:-$BUFFER}

  # Return immediately if the buffer was empty
  [[ -n $cmdline ]] || return 0
  
  local _spinner_interval _spinner_render_mode _spinner_message _spinner_type
  local -a _spinner_frames

  _spinner_interval=${_zsh_opencode_tab[spinner.interval_s]}
  _spinner_message=${_zsh_opencode_tab[spinner.message]}

  # Strip leading whitespace, then strip the magic prefix, then strip whitespace again.
  local user_request=${cmdline##[[:space:]]#}
  case "$kind" in
    keep)    user_request=${user_request#\#=} ;;
    explain) user_request=${user_request#\#\?} ;;
    *)       user_request=${user_request#\#} ;;
  esac
  user_request=${user_request##[[:space:]]#}

  local mode=1
  [[ "$kind" == "explain" ]] && mode=2

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

    # Execute opencode wrapper in a background subshell.
    # Disown the job to prevent job-control noise in the interactive shell.
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

      # Run the process
      local script="${_zsh_opencode_tab[dir]}/src/opencode_generate_command.py"
      local -a cmd
      cmd=(python3 "$script" \
        --user-request "$user_request" \
        --ostype "$OSTYPE" \
        --gnu "${_zsh_opencode_tab[opencode.gnu]}" \
        --mode "$mode" \
        --config-dir "${_zsh_opencode_tab[opencode.config_dir]}" \
        --backend "${_zsh_opencode_tab[opencode.attach]}" \
        --title "${_zsh_opencode_tab[opencode.title]}" \
        --agent "${_zsh_opencode_tab[opencode.agent]}"
      )

      [[ -n ${_zsh_opencode_tab[opencode.model]} ]] && cmd+=(--model "${_zsh_opencode_tab[opencode.model]}")
      [[ -n ${_zsh_opencode_tab[opencode.variant]} ]] && cmd+=(--variant "${_zsh_opencode_tab[opencode.variant]}")
      [[ -n ${_zsh_opencode_tab[opencode.log_level]} ]] && cmd+=(--log-level "${_zsh_opencode_tab[opencode.log_level]}")
      (( ${_zsh_opencode_tab[opencode.print_logs]} )) && cmd+=(--print-logs)
      (( ${_zsh_opencode_tab[opencode.delete_session]} )) && cmd+=(--delete-session)

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
    CURSOR=${#BUFFER}
    zle -R
    command rm -f -- "$out" 2>/dev/null
    return $rc
  fi

  # Success: parse the python output and put the generated command into the buffer.
  local output text session_id
  output=$(<"$out")
  command rm -f -- "$out" 2>/dev/null

  if (( ${_zsh_opencode_tab[debug]} )); then
    local dbg_file="${HOME}/debug.txt"
    {
      print -r -- "----- zsh-opencode-tab worker output -----"
      print -r -- "EPOCHSECONDS=$EPOCHSECONDS kind=$kind"
      print -r -- "$output"
      print -r -- "-----"
    } >>| "$dbg_file" 2>/dev/null
  fi

  # Output protocol from `src/opencode_generate_command.py`:
  # - Always: session_id + US + text + "\n"
  # - US is ASCII Unit Separator (0x1f). It's uncommon in normal text and
  #   therefore safe as a delimiter for arbitrary multi-line shell snippets.
  # - session_id may be empty; we currently ignore it, but keep it for future
  #   features and as a cheap integrity signal.
  output=${output%$'\n'}
  local US=$'\x1f'
  if [[ "$output" != *"$US"* ]]; then
    BUFFER="$cmdline"
    CURSOR=${#BUFFER}
    zle -R
    return 1
  fi

  session_id=${output%%"$US"*}
  text=${output#*"$US"}

  if [[ -z ${text//[[:space:]]/} ]]; then
    BUFFER="$cmdline"
    CURSOR=${#BUFFER}
    zle -R
    return 1
  fi

  if [[ "$kind" == "keep" ]]; then
    BUFFER="# $user_request"$'\n'"$text"
  elif [[ "$kind" == "explain" ]]; then
    local commented=""
    local line
    for line in ${(f)text}; do
      local raw=${line##[[:space:]]#}
      # If the model already returned comment-like output (or markdown headings
      # using #), normalize it so we don't end up with "# # # ...".
      while [[ $raw == \#* ]]; do
        raw=${raw#\#}
        raw=${raw##[[:space:]]#}
      done

      if [[ -n $raw ]]; then
        commented+="# $raw"$'\n'
      else
        commented+="#"$'\n'
      fi
    done
    BUFFER=${commented%$'\n'}
  else
    BUFFER="$text"
  fi
  CURSOR=${#BUFFER}
  zle -R
  return 0
}

# Backwards-compatible wrapper.
_zsh_opencode_tab_run_with_spinner() {
  _zsh_opencode_tab.run_with_spinner "$@"
}
