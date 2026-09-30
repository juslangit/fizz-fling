#!/usr/bin/env bash
# Rebuilds assets/sfx/ from the original CC0 downloads in art/audio-src/ (see SOURCES.md there):
# trimmed, loudness-matched, mono MP3s small enough for a phone browser.
set -euo pipefail
cd "$(dirname "$0")/.."
S=art/audio-src/freesound; P=art/audio-src/packs; O=assets/sfx; mkdir -p $O
enc() {  # in out loudness [start] [length] [extra filters]
  local af="${6:+$6,}loudnorm=I=$3:TP=-1.5"
  ffmpeg -v error -y ${4:+-ss $4} -i "$1" ${5:+-t $5} -af "$af" -ac 1 -ar 44100 -c:a libmp3lame -q:a 5 "$O/$2.mp3"
}
enc $S/pop.wav        pop       -12 0    0.7  "afade=t=out:st=0.45:d=0.25"
enc $S/spray.wav      spray     -16 0.05 1.9  "afade=t=out:st=1.4:d=0.5"
enc $S/cap_land.flac  cap_land  -16 0.95 1.1  "afade=t=out:st=0.8:d=0.3"
enc $S/cheer.wav      cheer     -15
enc $S/splash.mp3     splash    -18 0    1.2  "afade=t=out:st=0.8:d=0.4"
enc $S/slosh1.wav     slosh1    -17
enc $S/slosh2.wav     slosh2    -17
enc $S/slosh_long.aiff slosh3   -17 0    1.4  "afade=t=out:st=1.1:d=0.3"
# countdown beeps and the pressure-full ping: made here, no licence needed
ffmpeg -v error -y -f lavfi -i "aevalsrc='0.5*sin(2*PI*660*t)*exp(-9*t)':d=0.25:s=44100" -c:a libmp3lame -q:a 5 $O/beep.mp3
ffmpeg -v error -y -f lavfi -i "aevalsrc='0.5*sin(2*PI*990*t)*exp(-6*t)':d=0.4:s=44100" -c:a libmp3lame -q:a 5 $O/go.mp3
J=$P/music-jingles; I=$P/interface-sounds/Audio
cp "$(find $J -name 'jingles_PIZZI04.ogg' | head -1)" $O/win.ogg
cp "$(find $J -name 'jingles_STEEL00.ogg' | head -1)" $O/best.ogg
cp $I/click_002.ogg $O/click.ogg
du -sh $O; ls $O
