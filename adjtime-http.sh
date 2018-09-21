#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
#  re:tardis - Sync time via HTTP
#  Copyright (C) 2016  Marcel Krause <mk@pimpmybyte.de>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.


function retardis () {
  local DBGLV="${DEBUGLEVEL:-0}"
  local -A CFG
  local SERVERS=()
  read_config <(defaults_ini) "$HOME"/.{,config/}adjtime-http.ini
  parse_cli_opts "$@" || return $?

  local ABOUT_URL=
  [ "${SERVERS[0]:0:6}" == about: ] && ABOUT_URL="${SERVERS[*]}"
  case "$ABOUT_URL" in
    about:help )
      echo 'H: INI settings can be overridden with `--option=value`.' \
        'To see the defaults, give `about:defaults.ini` as only argument.'
      echo 'H: Additional options: --quiet --verbose'
      return 0;;
    about:defaults.ini ) defaults_ini; return 0;;
  esac

  local FIX_TIMEZONE_SED="$(gen_fix_timezone_sed)"
  config_calc {min,max}-delta || return $?
  case "$ABOUT_URL" in
    about:config )
      defaults_ini --head
      for ABOUT_URL in "${!CFG[@]}"; do
        printf '% 11s = %s\n' "$ABOUT_URL" "${CFG[$ABOUT_URL]}"
      done | sed -re 's~\s+$~~' | LANG=C sort
      return 0;;
  esac

  adjust_by_httphdr "${SERVERS[@]}"
  return $?
}


function defaults_ini () {
  local INI='[re:tardis]'
  case "$1" in
    --head ) ;;
    '' ) INI+="
      min-delta   = 5
      ; ^-- [seconds] Don't adjust if time differs less than this.
      max-delta   = 12 * 3600
      ; ^-- [seconds] If time differs more than this, assume server error.
      no-timezone = GMT
      ; ^-- Which timezone to assume if not specified by server.
      user-agent  = adjtime-http/0.2 (re:tardis)
      http-method = HEAD
      net-timeout = 30
      default-url = /cgi-bin/date-header
      noadjust-rv = 0
      ; ^-- Select a custom return value to indicate that time differed
      ;     less than min-delta. Numbers 30..69 are reserved for this.
      noadjust-kw =
      ; ^-- In above case, print this keyword to on a line by itself.
      adjusted-rv = 0
      adjusted-kw =
      ; ^-- Like noadjust-{rv,kw} but for when time has been adjusted.
      ";;
  esac
  INI="${INI//$'\n'      /$'\n'}"
  echo "$INI"
}


function read_config () {
  eval "$(sed -nre '
    s~\s+$~~
    s~\x27~&\\&&~g;s~$~\x27~
    s~^\s*([a-z0-9-]+)\s*[=:]\s*~CFG[\1]=\x27~p
    ' -- "$@" 2>/dev/null)"
}


function config_calc () {
  local OPT=
  local NUM=
  for OPT in "$@"; do
    NUM=
    let NUM="${CFG[$OPT]}"
    [ -n "$NUM" ] || return 3$(
      echo "E: bad number for option $OPT: '${CFG[$OPT]}'" >&2)
    CFG["$OPT"]="$NUM"
  done
  return 0
}


function parse_cli_opts () {
  local OPT=
  while [ "$#" -gt 0 ]; do
    OPT="$1"; shift
    case "$OPT" in
      '' ) continue;;
      --quiet )
        [ "$DBGLV" -ge 2 ] && echo "D: --quiet: debuglevel [$DBGLV]->[-1]" >&2
        DBGLV=-1;;
      --verbose )
        if [ "$DBGLV" -ge 2 ]; then
          echo "D: --verbose: skip: debuglevel $DBGLV already" >&2
        else
          DBGLV=1
        fi;;
      --*=* )
        OPT="${OPT#--}"
        CFG["${OPT%%=*}"]="${OPT#*=}";;
      --help ) SERVERS=( about:help );;
      -* ) echo "E: $0: unsupported option: $OPT" >&2; return 1;;
      * ) SERVERS+=( "$OPT" );;
    esac
  done
  return 0
}


function gen_fix_timezone_sed () {
  local FTZ='
    s!\s+! !g
    s~^(Æ ){2}¹{1,2} ²:²:² ¢$~none~p
    '
  FTZ="${FTZ//Æ/[A-Z][a-z]+}"
  FTZ="${FTZ//¹/[0-9]}"
  FTZ="${FTZ//²/[0-9]\{2\}}"
  FTZ="${FTZ//¢/[1-5][0-9]\{3\}}"    # century
  echo "$FTZ"
}


function request_httphdr () {
  local SRV="$1"
  SRV="${SRV#http://}"
  local URL="${CFG[default-url]%/}"
  case "$SRV" in
    */* ) URL="/${SRV#*/}"; SRV="/${SRV%%/*}";;
  esac
  [ -n "$SRV" ] || return 3$(echo "E: no hostname in URL '$URL'" >&2)

  local REQ="${CFG[http-method]} $URL HTTP/1.1"$'\r\n'
  REQ+="Host: $SRV"$'\r\n'
  REQ+="Connection: close"$'\r\n'
  REQ+=$'\r'   # blank line at end of request
  [[ "$SRV" =~ :[0-9]+$ ]] || SRV+=:80
  local NC_CMD=(
    timeout --signal HUP "${CFG[net-timeout]}"s
    stdbuf -o0 -e0
    netcat -q "${CFG[net-timeout]}"
    )
  local NC_MAX_VERBOSITY=vvvv
  [ "$DBGLV" -ge 2 ] && NC_CMD+=( "-${NC_MAX_VERBOSITY:0:$DBGLV}" )
  NC_CMD+=( "${SRV%:*}" "${SRV##*:}" )
  [ "$DBGLV" -ge 2 ] && echo "D: request command: ${NC_CMD[*]}" >&2
  [ "$DBGLV" -ge 3 ] && echo "D: request text: '${REQ//$'\r'/«}'" >&2
  local REQ_START="$(date +%s)"
  local RPL="$(sed -ure '/^\r?$/q' -- <(
    ( sleep 1s; echo "$REQ" ) | "${NC_CMD[@]}") )"
  local REQ_END="$(date +%s)"
  local REQ_DURA='?'
  let REQ_DURA="$REQ_END-$REQ_START"
  REQ_DATE="$(<<<"$RPL" sed -nre 's~\s+$~~g;/^$/q;s~^Date:\s+~~p')"
  if [ -z "$REQ_DATE" ]; then
    [ "$DBGLV" -ge 0 ] && echo "E: no date header was received from server" \
      "within $REQ_DURA seconds: $SRV" >&2
    [ "$DBGLV" -ge 1 ] && <<<"$RPL" head -n "$DBGLV" | nl -ba >&2
    return 2
  fi
  [ "$DBGLV" -ge 1 ] && echo "I: date header received from '$SRV': '$REQ_DATE'"
  local FIX_TS="$(<<<"$REQ_DATE" sed -nre "$FIX_TIMEZONE_SED")"
  case "$FIX_TS" in
    '' ) ;;
    none )
      FIX_TS="${CFG[no-timezone]}"
      [ "$DBGLV" -ge 0 ] && echo "W: date header had no timezone!" \
        "assuming '$FIX_TS'." >&2
      REQ_DATE+=" $FIX_TS";;
    *' '* ) REQ_DATE="$FIX_TS";;
    * ) REQ_DATE+=" $FIX_TS";;
  esac
  HTTP_TS=( reply "$REQ_START" "$REQ_END" "$REQ_DURA" mid_uts adjust_sec )
  # slots:  0     1            2          3           4       5
  HTTP_TS[0]="$(date +%s --date="$REQ_DATE")"
  [ -n "${HTTP_TS[0]}" ] || return 3$([ "$DBGLV" -ge 0 ] \
    && echo "E: unable to convert date header to unix timestamp." >&2)
  let HTTP_TS[4]="${HTTP_TS[1]}+(${HTTP_TS[3]}/2)"
    # ^-- (a+b)/2 could overflow in sum
  let DELTA="${HTTP_TS[0]}-${HTTP_TS[4]}"
  [ "$DELTA" == 0 ] || [ "${DELTA:0:1}" == - ] || DELTA="+$DELTA"
  HTTP_TS[5]="$DELTA"
  [ "$DBGLV" -ge 0 ] && echo "I: date header differs by ${HTTP_TS[5]} seconds."
  return 0
}


function adjust_by_httphdr () {
  local HTTP_TS=()
  local DELTA_SEC=
  local DELTA_ABS=
  local SRV=
  for SRV in "$@"; do
    HTTP_TS=()
    request_httphdr "$SRV" || continue
    DELTA_SEC="${HTTP_TS[5]}"
    DELTA_ABS="${DELTA_SEC#[+-]}"
    if [ "$DELTA_ABS" -lt "${CFG[min-delta]}" ]; then
      [ "$DBGLV" -ge 0 ] && echo 'I: time differs by less than' \
        "${CFG[min-delta]} seconds, that's good enough."
      [ -n "${CFG[noadjust-kw]}" ] && echo "${CFG[noadjust-kw]}"
      return "${CFG[noadjust-rv]:-0}"
      return 0
    elif [ "$DELTA_ABS" -gt "${CFG[max-delta]}" ]; then
      [ "$DBGLV" -ge 0 ] && echo 'I: server time differs by more than' \
        "${CFG[max-delta]} seconds, can't trust that."
      continue
    fi
    DELTA_ABS='DELTA="$(date +%s --date="'"$DELTA_SEC"' seconds")"; '
    DELTA_ABS+='[ -n "$DELTA" ] && date -R --set "@$DELTA"'
    if sudo -E sh -c "$DELTA_ABS"; then
      [ -n "${CFG[adjusted-kw]}" ] && echo "${CFG[adjusted-kw]}"
      return "${CFG[adjusted-rv]:-0}"
      return 0
    fi
  done
  return 5
}















retardis "$@"; exit $?
