#!/hint/zsh

# Copyright (c) 2026, Andrea Alberti (MIT license)

# ZLE Knight Rider Spinner (rendering only)
#
# This file intentionally contains *no* process control logic.
# The controller owns:
# - starting/stopping the background process
# - reading the status FIFO
# - Ctrl-C handling + escalation
# - pacing (frame deadlines)
#
# This file provides:
# - init (cursor hide + palette precompute)
# - draw one frame
# - cleanup (cursor restore + clear ZLE line)

## Configuration
# This module renders only.
# All user-facing configuration lives in `_zsh_opencode_tab[...]` and is resolved
# when the plugin is loaded (see `zsh-opencode-tab.plugin.zsh`).

function _zsh_opencode_tab.spinner.total_frames() {
  emulate -L zsh

  local -i viewLen=${1:-${_zsh_opencode_tab[spinner.viewLen]}}
  local -i padR=${2:-${_zsh_opencode_tab[spinner.padR]}}
  local -i padL=${3:-${_zsh_opencode_tab[spinner.padL]}}

  # forward(viewLen) + holdEnd(padR) + backward(viewLen-1) + holdStart(padL)
  REPLY=$(( viewLen + padR + (viewLen - 1) + padL ))
}

function _zsh_opencode_tab.spinner.__hsv_to_hex() {
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

function _zsh_opencode_tab.spinner.__hsv_to_rgb() {
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

function _zsh_opencode_tab.spinner.__rgb_to_hex() {
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
# - _zsh_opencode_tab_spinner_trail_palette: list of pre-blended hex colors for trail steps
# - _zsh_opencode_tab_spinner_inactive_fg: pre-blended hex color for inactive dots (changes with fade)
# - _zsh_opencode_tab_spinner_base_*: base color in linear-ish RGB floats
# - _zsh_opencode_tab_spinner_bg_*: background RGB floats derived from _zsh_opencode_tab_spinner_bg_hex
function _zsh_opencode_tab.spinner.__hex_to_rgb() {
  emulate -L zsh

  # Convert '#RRGGBB' (or 'RRGGBB') to RGB floats in 0..1.
  # Output is placed in `reply=(r g b)`.

  local hex=${1#\#}
  local -i r=$(( 16#${hex[1,2]} ))
  local -i g=$(( 16#${hex[3,4]} ))
  local -i b=$(( 16#${hex[5,6]} ))

  reply=($(( r / 255.0 )) $(( g / 255.0 )) $(( b / 255.0 )))
}

function _zsh_opencode_tab.spinner.__set_bg() {
  emulate -L zsh

  _zsh_opencode_tab.spinner.__hex_to_rgb ${_zsh_opencode_tab[spinner.bg_hex]}
  _zsh_opencode_tab[spinner.state.bg_r]=${reply[1]}
  _zsh_opencode_tab[spinner.state.bg_g]=${reply[2]}
  _zsh_opencode_tab[spinner.state.bg_b]=${reply[3]}
}

function _zsh_opencode_tab.spinner.__set_inactive_fg() {
  emulate -L zsh

  # Compute the inactive dot foreground color for this frame.
  #
  # Upstream uses alpha on an RGBA color. Terminals do not have alpha, so we
  # approximate by blending with the configured background:
  #   final = alpha * base + (1 - alpha) * bg
  # where:
  #   alpha = _zsh_opencode_tab_spinner_inactive_factor * fadeFactor

  local -F fadeFactor=$1

  local -F base_r=${_zsh_opencode_tab[spinner.state.base_r]}
  local -F base_g=${_zsh_opencode_tab[spinner.state.base_g]}
  local -F base_b=${_zsh_opencode_tab[spinner.state.base_b]}
  local -F bg_r=${_zsh_opencode_tab[spinner.state.bg_r]}
  local -F bg_g=${_zsh_opencode_tab[spinner.state.bg_g]}
  local -F bg_b=${_zsh_opencode_tab[spinner.state.bg_b]}
  local -F inactive_factor=${_zsh_opencode_tab[spinner.inactive_factor]}

  local -F alpha=$(( inactive_factor * fadeFactor ))
  local -F inv=$(( 1.0 - alpha ))
  local -F r=$(( base_r * alpha + bg_r * inv ))
  local -F g=$(( base_g * alpha + bg_g * inv ))
  local -F b=$(( base_b * alpha + bg_b * inv ))

  _zsh_opencode_tab.spinner.__rgb_to_hex $r $g $b
  _zsh_opencode_tab[spinner.state.inactive_fg]=$REPLY
}

function _zsh_opencode_tab.spinner.__derive_trail_palette() {
  emulate -L zsh

  # Derive the trail palette from a single base HSV color.
  # This ports the `deriveTrailColors` logic from spinner.ts.
  #
  # Trail steps (i = 0..trailLen-1):
  # - i==0: alpha=1.0, brightness=1.0 (head)
  # - i==1: alpha=0.9, brightness=1.15 (glare / bloom)
  # - i>=2: alpha=0.65^(i-1), brightness=1.0 (exponential fade)
  #
  # Each step is pre-blended against _zsh_opencode_tab_spinner_bg_hex (RGBA -> RGB on bg).

  local -i trailLen=$1

  _zsh_opencode_tab.spinner.__set_bg

  local -F hue=${_zsh_opencode_tab[spinner.hue]}
  local -F sat=${_zsh_opencode_tab[spinner.saturation]}
  local -F val=${_zsh_opencode_tab[spinner.value]}
  _zsh_opencode_tab.spinner.__hsv_to_rgb $hue $sat $val
  local -F baseR=${reply[1]}
  local -F baseG=${reply[2]}
  local -F baseB=${reply[3]}

  _zsh_opencode_tab[spinner.state.base_r]=$baseR
  _zsh_opencode_tab[spinner.state.base_g]=$baseG
  _zsh_opencode_tab[spinner.state.base_b]=$baseB

  local -F bg_r=${_zsh_opencode_tab[spinner.state.bg_r]}
  local -F bg_g=${_zsh_opencode_tab[spinner.state.bg_g]}
  local -F bg_b=${_zsh_opencode_tab[spinner.state.bg_b]}

  local -F r g b alpha bright
  local -F inv
  local -i i

  local -a palette
  palette=()
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
    (( r = r * alpha + bg_r * inv ))
    (( g = g * alpha + bg_g * inv ))
    (( b = b * alpha + bg_b * inv ))

    _zsh_opencode_tab.spinner.__rgb_to_hex $r $g $b
    palette+=($REPLY)
  done

  _zsh_opencode_tab.spinner.__set_inactive_fg 1.0

_zsh_opencode_tab[spinner.state.trail_palette]="${(j: :)palette}"
}

# Backwards-compatible wrappers.
_zsh_opencode_tab_spinner_total_frames() { _zsh_opencode_tab.spinner.total_frames "$@" }
_zsh_opencode_tab_spinner_init() { _zsh_opencode_tab.spinner.init "$@" }
_zsh_opencode_tab_spinner_draw_frame() { _zsh_opencode_tab.spinner.draw_frame "$@" }
_zsh_opencode_tab_spinner_cleanup() { _zsh_opencode_tab.spinner.cleanup "$@" }

function _zsh_opencode_tab.spinner.__train_frame() {
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

  local dot_char=${_zsh_opencode_tab[spinner.dot_char]}
  local train_char=${_zsh_opencode_tab[spinner.train_char]}
  local barBg=${_zsh_opencode_tab[spinner.bg_hex]}
  local msg=${_zsh_opencode_tab[spinner.message]}
  local msgFg=${_zsh_opencode_tab[spinner.message_fg]}

  local -a trail_palette
  trail_palette=( ${=_zsh_opencode_tab[spinner.state.trail_palette]} )
  local inactive_fg=${_zsh_opencode_tab[spinner.state.inactive_fg]}

  # The visible interior is built as plain text first (dots), then some
  # positions are replaced with the active block character.

  local view="${(l:$viewLen:: :)""}"
  view=${view// /${dot_char}}

  local bracketFg=${trail_palette[2]:-${trail_palette[1]}}
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
    "1 $(( viewLen + 1 )) fg=${inactive_fg},bg=${barBg}"
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
      view[$viewIdx]=${train_char}
      reply+=( "$viewIdx $(( viewIdx + 1 )) fg=${trail_palette[$(( idx + 1 ))]},bg=${barBg}" )
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

_zsh_opencode_tab.spinner.init() {
  emulate -L zsh

  # Precompute palette and background blending state.
  _zsh_opencode_tab.spinner.__derive_trail_palette ${_zsh_opencode_tab[spinner.trailLen]}

  # Hide cursor while animating.
  if (( ${+terminfo[civis]} )); then
    print -n -- $terminfo[civis]
  else
    print -n -- $'\e[?25l'
  fi
}

_zsh_opencode_tab.spinner.draw_frame() {
  emulate -L zsh

  # Draw a single frame given a monotonically increasing frame counter.
  # The modulo by totalFrames creates a repeating cycle.
  local -i frameCount=$1

  local -i padL=${_zsh_opencode_tab[spinner.padL]}
  local -i padR=${_zsh_opencode_tab[spinner.padR]}
  local -i viewLen=${_zsh_opencode_tab[spinner.viewLen]}
  local -i trailLen=${_zsh_opencode_tab[spinner.trailLen]}

  _zsh_opencode_tab.spinner.total_frames $viewLen $padR $padL
  local -i totalFrames=$REPLY

  local -i frameIndex=$(( frameCount % totalFrames ))
  local -i activePos dir
  local -i isHolding holdProgress holdTotal
  local -i movementProgress movementTotal
  local -F progress fadeFactor

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

  # Global fade for inactive dots.
  fadeFactor=1.0
  if (( ${_zsh_opencode_tab[spinner.enable_fading]} )); then
    if (( isHolding )) && (( holdTotal > 0 )); then
      progress=$(( holdProgress / (holdTotal * 1.0) ))
      local -F min_alpha=${_zsh_opencode_tab[spinner.min_alpha]}
      fadeFactor=$(( 1.0 - progress * (1.0 - min_alpha) ))
      (( fadeFactor < min_alpha )) && fadeFactor=$min_alpha
    elif (( ! isHolding )) && (( movementTotal > 0 )); then
      progress=$(( movementProgress / ((movementTotal > 1 ? (movementTotal - 1) : 1) * 1.0) ))
      local -F min_alpha2=${_zsh_opencode_tab[spinner.min_alpha]}
      fadeFactor=$(( min_alpha2 + progress * (1.0 - min_alpha2) ))
    fi
  fi
  _zsh_opencode_tab.spinner.__set_inactive_fg $fadeFactor

  # Build and render.
  _zsh_opencode_tab.spinner.__train_frame $padL $padR $trailLen $viewLen $activePos $dir $isHolding $holdProgress
  BUFFER="$REPLY"
  CURSOR=0
  POSTDISPLAY=""
  region_highlight=("${reply[@]}")
  zle -R
}

_zsh_opencode_tab.spinner.cleanup() {
  emulate -L zsh

  # Restore cursor.
  if (( ${+terminfo[cnorm]} )); then
    print -n -- $terminfo[cnorm]
  else
    print -n -- $'\e[?25h'
  fi

  # Clear the command line.
  BUFFER=""
  CURSOR=0
  POSTDISPLAY=""
  region_highlight=()
  zle -R
}
