#!/bin/bash
musicdir=/library/music
scriptname=$(realpath "$0" 2>/dev/null)

function editscript(){
  local script path; script="${scriptname##*/}"; path="${scriptname%/*}"; swp="$path/.$script.swp"
     if [[ ! -e "$swp" ]]; then printf "\n\n%s\n\n" "$swp"; (/usr/bin/nano "$scriptname"); exit
     else printf "\n%s is already being edited.\n%s exists; try fg or look in another window.\n" "$scriptname" "$swp"; exit;
  fi; }

function pause(){ read -p "$*" ; }

if [[ "$1" == @(edit|e|nano) ]]; then editscript; fi

artist="$(mpc current -f %artist%)"
album="$(mpc current -f %album%)"
title="$(mpc current -f %title%)"
printf "\n\033[0mArtist: %s\nAlbum : %s\nTitle : %s\n" "$artist" "$album" "$title"

mpc current -f "%file%"|awk -F / -v OFS=/ '{$1="\033[1;33m" $1 "\033[0m"; $NF="\033[1;34m" $NF "\033[0m"; print}'

#mpc current -f "%title% on %album% by %artist%\n%file%"
printf '\n'
mpc queued -f "%file%"|awk -F / -v OFS=/ '{$1="Up next: \033[1;33m" $1 "\033[0m"; $NF="\033[1;34m" $NF "\033[0m"; print}'
printf '\n'

n=0

while read -r line
  do
    i="${line/ : player: /\/ }"
    i=$(printf '%s' "$i"|awk -F / -v OFS=/ '{$1="\033[1;32m" $1 "\033[0m"; $2 = "\033[1;33m" $2 "\033[0m"; $NF = "\033[1;34m" $NF "\033[0m"; print}')
    i="${i/\//:}"
#    printf '%s\n' "$i"
    playedarr["$n"]="$i"
    ((n++))
  done < <(tail -100 /var/log/mpd/mpd.log|\grep player)

j=$(gum choose --height 40 "${playedarr[@]}") || exit
j="${j%\"*}"
j="${j#*: \"}"
d="${j%/*}"

echo "$j"

exitapp=$(gum choose "mediainfo" "picard" "cd ${d}")
 if [[ "$exitapp" == mediainfo ]]
   then
     mediainfo "/library/music/$j"
   elif
     [[ "$exitapp" == picard ]]; then picard "$musicdir/$d"
   elif
     [[ "$exitapp" == "cd $d" ]]; then cd "/library/music/$d"
 fi

