# ZLE-based Knight Rider bar demo.
#
# Key ideas:
# - Never write the animation directly to /dev/tty while ZLE is active.
# - Render via ZLE: set BUFFER, then call `zle -R`.
# - Apply color via `region_highlight` (supports fg/bg and truecolor hex).
# - Keep the input line empty when done.
#
# This file is meant to be sourced from an interactive zsh:
#   source ./test.zsh
# then press Ctrl-G (see bindkey at the bottom).

# Characters used for the inactive background and the active trail blocks.
_overlay_dot_char='.'
_overlay_train_char='■'

# Base color for the effect is configured in HSV.
# The trail palette is derived from this single bright color.
_overlay_hue=270            # 0..360 (degrees)
_overlay_saturation=0.75    # 0..1
_overlay_value=1.0          # 0..1

# Inactive dots are a dimmed version of the base color.
# In upstream code this is alpha (opacity). In terminals we simulate alpha by
# blending with a configured background, see `_overlay_bg_hex`.
_overlay_inactive_factor=0.4  # 0..1

# Global fading for inactive dots (like opencode):
# - during movement: fade in from minAlpha to 1
# - during holds: fade out from 1 to minAlpha
_overlay_enable_fading=1     # 1=true, 0=false
_overlay_min_alpha=0.0       # 0..1

# Background color used for alpha blending and (optionally) as the bar's bg.
# This must match (or be close to) your terminal background if you want the
# alpha-like fades to look like the upstream RGBA implementation.
_overlay_bg_hex='#111111'    # '#RRGGBB'

# Real-time pacing. We poll frequently, but only render when a frame deadline
# expires so the animation speed is consistent across tmux vs non-tmux.
_overlay_frame_ms=33         # target frame duration (ms)
_overlay_poll_cs=1           # zselect -t units (centiseconds); 1 => 10ms

# Optional message shown after the bar.
# Example: _overlay_message='Please wait for the agent ...'
_overlay_message='Please wait ...'

# Optional message foreground color (truecolor hex like '#cfcfcf').
# Empty string means: do not apply any special fg.
_overlay_message_fg=''

function _overlay_hsv_to_hex() {
  emulate -L zsh

  # Convert HSV (h in degrees, s/v in 0..1) to a '#RRGGBB' hex string.
  # Output is placed in REPLY.

  local -F h=$1
  local -F s=$2
  local -F v=$3

  (( h = h % 360.0 ))
  (( h < 0.0 )) && (( h += 360.0 ))

  local -F c x m hprime h2 hmod t
  local -F r1 g1 b1
  local -F r g b
  local -i sector

  (( c = v * s ))
  (( hprime = h / 60.0 ))
  (( sector = hprime ))
  (( h2 = hprime / 2.0 ))
  local -i k=$h2
  (( hmod = hprime - 2.0 * k ))
  (( t = hmod - 1.0 ))
  (( t < 0.0 )) && (( t = -t ))
  (( x = c * (1.0 - t) ))
  (( m = v - c ))

  case $sector in
    0) r1=$c; g1=$x; b1=0.0 ;;
    1) r1=$x; g1=$c; b1=0.0 ;;
    2) r1=0.0; g1=$c; b1=$x ;;
    3) r1=0.0; g1=$x; b1=$c ;;
    4) r1=$x; g1=0.0; b1=$c ;;
    *) r1=$c; g1=0.0; b1=$x ;;
  esac

  (( r = (r1 + m) * 255.0 ))
  (( g = (g1 + m) * 255.0 ))
  (( b = (b1 + m) * 255.0 ))

  local -i ri=$(( r + 0.5 ))
  local -i gi=$(( g + 0.5 ))
  local -i bi=$(( b + 0.5 ))

  printf -v REPLY '#%02X%02X%02X' $ri $gi $bi
}

function _overlay_hsv_to_rgb() {
  emulate -L zsh
  
  # Convert HSV to RGB floats in 0..1.
  # Output is placed in the array `reply=(r g b)`.

  local -F h=$1
  local -F s=$2
  local -F v=$3

  (( h = h % 360.0 ))
  (( h < 0.0 )) && (( h += 360.0 ))

  local -F c x m hprime h2 hmod t
  local -F r1 g1 b1
  local -F r g b
  local -i sector

  (( c = v * s ))
  (( hprime = h / 60.0 ))
  (( sector = hprime ))
  (( h2 = hprime / 2.0 ))
  local -i k=$h2
  (( hmod = hprime - 2.0 * k ))
  (( t = hmod - 1.0 ))
  (( t < 0.0 )) && (( t = -t ))
  (( x = c * (1.0 - t) ))
  (( m = v - c ))

  case $sector in
    0) r1=$c; g1=$x; b1=0.0 ;;
    1) r1=$x; g1=$c; b1=0.0 ;;
    2) r1=0.0; g1=$c; b1=$x ;;
    3) r1=0.0; g1=$x; b1=$c ;;
    4) r1=$x; g1=0.0; b1=$c ;;
    *) r1=$c; g1=0.0; b1=$x ;;
  esac

  (( r = r1 + m ))
  (( g = g1 + m ))
  (( b = b1 + m ))

  reply=($r $g $b)
}

function _overlay_rgb_to_hex() {
  emulate -L zsh
  
  # Convert RGB floats (0..1) to '#RRGGBB'.
  # Values are clamped before conversion.
  # Output is placed in REPLY.

  local -F r=$1
  local -F g=$2
  local -F b=$3

  (( r < 0.0 )) && r=0.0
  (( g < 0.0 )) && g=0.0
  (( b < 0.0 )) && b=0.0
  (( r > 1.0 )) && r=1.0
  (( g > 1.0 )) && g=1.0
  (( b > 1.0 )) && b=1.0

  local -i ri=$(( r * 255.0 + 0.5 ))
  local -i gi=$(( g * 255.0 + 0.5 ))
  local -i bi=$(( b * 255.0 + 0.5 ))

  printf -v REPLY '#%02X%02X%02X' $ri $gi $bi
}

# Global state (computed once per run, then updated per frame):
# - _overlay_trail_palette: list of pre-blended hex colors for trail steps
# - _overlay_inactive_fg: pre-blended hex color for inactive dots (changes with fade)
# - _overlay_base_*: base color in linear-ish RGB floats
# - _overlay_bg_*: background RGB floats derived from _overlay_bg_hex
typeset -ga _overlay_trail_palette
typeset -g _overlay_inactive_fg
typeset -gF _overlay_base_r _overlay_base_g _overlay_base_b
typeset -gF _overlay_bg_r _overlay_bg_g _overlay_bg_b

function _overlay_hex_to_rgb() {
  emulate -L zsh
  
  # Convert '#RRGGBB' (or 'RRGGBB') to RGB floats in 0..1.
  # Output is placed in `reply=(r g b)`.

  local hex=${1#\#}
  local -i r=$(( 16#${hex[1,2]} ))
  local -i g=$(( 16#${hex[3,4]} ))
  local -i b=$(( 16#${hex[5,6]} ))

  reply=($(( r / 255.0 )) $(( g / 255.0 )) $(( b / 255.0 )))
}

function _overlay_set_bg() {
  emulate -L zsh
  
  # Parse _overlay_bg_hex into float RGB components used for blending.

  _overlay_hex_to_rgb $_overlay_bg_hex
  _overlay_bg_r=${reply[1]}
  _overlay_bg_g=${reply[2]}
  _overlay_bg_b=${reply[3]}
}

function _overlay_set_inactive_fg() {
  emulate -L zsh
  
  # Compute the inactive dot foreground color for this frame.
  #
  # Upstream uses alpha on an RGBA color. Terminals do not have alpha, so we
  # approximate by blending with the configured background:
  #   final = alpha * base + (1 - alpha) * bg
  # where:
  #   alpha = _overlay_inactive_factor * fadeFactor

  local -F fadeFactor=$1

  local -F alpha=$(( _overlay_inactive_factor * fadeFactor ))
  local -F inv=$(( 1.0 - alpha ))
  local -F r=$(( _overlay_base_r * alpha + _overlay_bg_r * inv ))
  local -F g=$(( _overlay_base_g * alpha + _overlay_bg_g * inv ))
  local -F b=$(( _overlay_base_b * alpha + _overlay_bg_b * inv ))

  _overlay_rgb_to_hex $r $g $b
  _overlay_inactive_fg=$REPLY
}

function _overlay_derive_trail_palette() {
  emulate -L zsh

  # Derive the trail palette from a single base HSV color.
  # This ports the `deriveTrailColors` logic from spinner.ts.
  #
  # Trail steps (i = 0..trailLen-1):
  # - i==0: alpha=1.0, brightness=1.0 (head)
  # - i==1: alpha=0.9, brightness=1.15 (glare / bloom)
  # - i>=2: alpha=0.65^(i-1), brightness=1.0 (exponential fade)
  #
  # Each step is pre-blended against _overlay_bg_hex (RGBA -> RGB on bg).

  local -i trailLen=$1

  _overlay_set_bg

  _overlay_hsv_to_rgb $_overlay_hue $_overlay_saturation $_overlay_value
  local -F baseR=${reply[1]}
  local -F baseG=${reply[2]}
  local -F baseB=${reply[3]}

  _overlay_base_r=$baseR
  _overlay_base_g=$baseG
  _overlay_base_b=$baseB

  local -F r g b alpha bright
  local -F inv
  local -i i

  _overlay_trail_palette=()
  for (( i = 0; i < trailLen; i++ )); do
    if (( i == 0 )); then
      alpha=1.0
      bright=1.0
    elif (( i == 1 )); then
      alpha=0.9
      bright=1.15
    else
      alpha=$(( 0.65 ** (i - 1) ))
      bright=1.0
    fi

    (( r = baseR * bright ))
    (( g = baseG * bright ))
    (( b = baseB * bright ))
    (( r > 1.0 )) && r=1.0
    (( g > 1.0 )) && g=1.0
    (( b > 1.0 )) && b=1.0

    (( inv = 1.0 - alpha ))
    (( r = r * alpha + _overlay_bg_r * inv ))
    (( g = g * alpha + _overlay_bg_g * inv ))
    (( b = b * alpha + _overlay_bg_b * inv ))

    _overlay_rgb_to_hex $r $g $b
    _overlay_trail_palette+=($REPLY)
  done

  _overlay_set_inactive_fg 1.0
}

function _overlay_train_frame() {
  emulate -L zsh
  
  # Render one frame of the bar.
  #
  # Inputs:
  # - padL/padR/viewLen: define a larger "world" and the visible window
  # - activePos: scanner head position in world coordinates (1-based)
  # - dir: +1 when moving forward, -1 when moving backward
  # - isHolding/holdProgress: used to "retract" the trail during holds
  #
  # Outputs:
  # - REPLY: full string to put into BUFFER (includes brackets and message)
  # - reply: array of region_highlight spans for this frame

  local -i padL=$1
  local -i padR=$2
  local -i trailLen=$3
  local -i viewLen=$4
  local -i activePos=$5
  local -i dir=$6
  local -i isHolding=$7
  local -i holdProgress=$8

  local -i viewStart=$(( padL + 1 ))
  local -i viewEnd=$(( padL + viewLen ))

  # The visible interior is built as plain text first (dots), then some
  # positions are replaced with the active block character.

  local view="${(l:$viewLen:: :)""}"
  view=${view// /${_overlay_dot_char}}

  local bracketFg=${_overlay_trail_palette[2]:-${_overlay_trail_palette[1]}}
  local barBg=$_overlay_bg_hex
  local msg=$_overlay_message
  local msgFg=$_overlay_message_fg
  local -i barLen=$(( viewLen + 2 ))

  # We highlight the bar in three layers:
  # 1) brackets (`[` and `]`) with a bright color (use the "glare" if available)
  # 2) baseline for the interior dots
  # 3) per-cell overrides for active trail blocks
  #
  # region_highlight format is:
  #   "start end style"
  # where start/end are 0-based, end is exclusive, and style is a comma-
  # separated list like "fg=#RRGGBB,bg=#RRGGBB".

  # Buffer is: [<viewLen chars>]
  reply=(
    "0 1 fg=${bracketFg},bg=${barBg}"
    "$(( viewLen + 1 )) $(( viewLen + 2 )) fg=${bracketFg},bg=${barBg}"
    "1 $(( viewLen + 1 )) fg=${_overlay_inactive_fg},bg=${barBg}"
  )

  local -i p
  for (( p = viewStart; p <= viewEnd; p++ )); do
    # Directional distance behind the head:
    # - moving forward: trail is to the left  => dist = activePos - p
    # - moving backward: trail is to the right => dist = p - activePos
    local -i dist
    if (( dir > 0 )); then
      dist=$(( activePos - p ))
    else
      dist=$(( p - activePos ))
    fi

    # Trail palette index.
    # During holds, we shift the index by holdProgress so the trail appears to
    # fade/retract even though the head is stationary (matches spinner.ts).
    local -i idx=$dist
    if (( isHolding )); then
      idx=$(( idx + holdProgress ))
    fi

    # idx==0 is the bright head color. idx>0 are tail colors.
    if (( idx >= 0 && idx < trailLen )); then
      local -i viewIdx=$(( p - padL ))
      view[$viewIdx]=${_overlay_train_char}
      reply+=( "$viewIdx $(( viewIdx + 1 )) fg=${_overlay_trail_palette[$(( idx + 1 ))]},bg=${barBg}" )
    fi
  done

  if [[ -n $msg ]]; then
    # Message is not part of the bar background by default.
    # Apply a message fg color only if configured.
    REPLY="[${view}] ${msg}"
    if [[ -n $msgFg ]]; then
      reply+=( "${barLen} ${#REPLY} fg=${msgFg}" )
    fi
  else
    REPLY="[${view}]"
  fi
}

function _knight_rider_widget() {
  emulate -L zsh
  
  # ZLE widget entrypoint.
  # Runs a short animation on the current command line, then clears the line.
  #
  # We intentionally keep the buffer empty at the end.
  local -i have_zselect=0
  zmodload -F zsh/zselect b:zselect 2>/dev/null && have_zselect=1

  local method
  if (( have_zselect )); then
    method=zselect
  else
    method=sleep
  fi

  # Timing is done via EPOCHREALTIME with a frame deadline.
  # We poll frequently (zselect -t in centiseconds), but only advance when the
  # deadline is reached, so tmux vs non-tmux rendering speed doesn't change the
  # animation's real-world speed.

  local -F 6 t0 t1 dt
  t0=${EPOCHREALTIME:-$SECONDS}

  # Defaults chosen to match spinner.ts:
  # - viewLen (width) = 8
  # - padR (holdEnd) = 9
  # - padL (holdStart) = 30
  # - trainLen (trail steps) = 6
  local -i padL=30
  local -i padR=9
  local -i viewLen=8
  local -i trainLen=6

  # One complete cycle is:
  # - forward: viewLen frames
  # - holdEnd: padR frames
  # - backward: viewLen-1 frames
  # - holdStart: padL frames
  local -i totalFrames=$(( viewLen + padR + (viewLen - 1) + padL ))

  # How many frames to render (multiple cycles for easier visual testing).
  local -i steps=$(( totalFrames * 3 ))

  _overlay_derive_trail_palette $trainLen

  local -i frameIndex
  local -i activePos dir
  local -i isHolding holdProgress holdTotal
  local -i movementProgress movementTotal
  local -F progress fadeFactor
  local -F now next_deadline frame_s
  frame_s=$(( _overlay_frame_ms / 1000.0 ))
  now=${EPOCHREALTIME:-$SECONDS}
  next_deadline=$now

  {
    # Hide cursor
    if (( ${+terminfo[civis]} )); then
      print -n -- $terminfo[civis]
    else
      print -n -- $'\e[?25l'
    fi
    local -i i=0
    while (( i < steps )); do
      now=${EPOCHREALTIME:-$SECONDS}

      # Wait until the current frame's deadline. We poll instead of sleeping
      # the full remaining time so we can remain responsive in slow terminals.
      if (( now < next_deadline )); then
        if (( have_zselect )); then
          zselect -t $_overlay_poll_cs
        else
          sleep 0.01
        fi
        continue
      fi

      (( frameIndex = i % totalFrames ))

      # Port of spinner.ts getScannerState(), with padL/padR mapped to
      # holdStart/holdEnd. activePos is expressed in world coordinates.

      if (( frameIndex < viewLen )); then
        # Moving forward
        activePos=$(( padL + 1 + frameIndex ))
        dir=1
        isHolding=0
        holdProgress=0
        holdTotal=0
        movementProgress=$frameIndex
        movementTotal=$viewLen
      elif (( frameIndex < viewLen + padR )); then
        # Holding at end
        activePos=$(( padL + viewLen ))
        dir=1
        isHolding=1
        holdProgress=$(( frameIndex - viewLen ))
        holdTotal=$padR
        movementProgress=0
        movementTotal=0
      elif (( frameIndex < viewLen + padR + (viewLen - 1) )); then
        # Moving backward
        local -i backwardIndex=$(( frameIndex - viewLen - padR ))
        activePos=$(( padL + viewLen - 1 - backwardIndex ))
        dir=-1
        isHolding=0
        holdProgress=0
        holdTotal=0
        movementProgress=$backwardIndex
        movementTotal=$(( viewLen - 1 ))
      else
        # Holding at start
        activePos=$(( padL + 1 ))
        dir=-1
        isHolding=1
        holdProgress=$(( frameIndex - viewLen - padR - (viewLen - 1) ))
        holdTotal=$padL
        movementProgress=0
        movementTotal=0
      fi

      # Fade inactive dots globally. This ports the upstream logic:
      # - hold: fade out from 1 -> minAlpha
      # - movement: fade in from minAlpha -> 1
      fadeFactor=1.0
      if (( _overlay_enable_fading )); then
        if (( isHolding )) && (( holdTotal > 0 )); then
          progress=$(( holdProgress / (holdTotal * 1.0) ))
          fadeFactor=$(( 1.0 - progress * (1.0 - _overlay_min_alpha) ))
          (( fadeFactor < _overlay_min_alpha )) && fadeFactor=$_overlay_min_alpha
        elif (( ! isHolding )) && (( movementTotal > 0 )); then
          progress=$(( movementProgress / ((movementTotal > 1 ? (movementTotal - 1) : 1) * 1.0) ))
          fadeFactor=$(( _overlay_min_alpha + progress * (1.0 - _overlay_min_alpha) ))
        fi
      fi
      _overlay_set_inactive_fg $fadeFactor

      # Build the next frame's text and highlighting.
      _overlay_train_frame $padL $padR $trainLen $viewLen $activePos $dir $isHolding $holdProgress

      # Render through ZLE.
      BUFFER="$REPLY"
      CURSOR=0
      POSTDISPLAY=""
      region_highlight=("${reply[@]}")

      zle -R

      # Advance to the next frame and compute the next deadline.
      (( i++ ))
      (( next_deadline += frame_s ))
      if (( next_deadline < now )); then
        next_deadline=$(( now + frame_s ))
      fi

    done
  } always {
    # Restore cursor
    if (( ${+terminfo[cnorm]} )); then
      print -n -- $terminfo[cnorm]
    else
      print -n -- $'\e[?25h'
    fi
  }

  t1=${EPOCHREALTIME:-$SECONDS}
  dt=$(( t1 - t0 ))
  zle -M "overlay: method=${method}, totalFrames=${totalFrames}, steps=${steps}, elapsed=$(( dt * 1000 ))ms"

  # Cleanup: keep the input line empty.
  BUFFER=""
  CURSOR=0
  POSTDISPLAY=""
  region_highlight=()
  zle -R
}

zle -N _knight_rider_widget

bindkey '^G' _knight_rider_widget
