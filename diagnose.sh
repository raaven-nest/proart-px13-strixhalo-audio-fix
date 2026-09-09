#!/usr/bin/env bash
# Collect audio diagnostics for the ASUS ProArt PX13 (Strix Halo).
# Paste the output into a GitHub issue or an upstream (linux-sound) bug report.
# Run with sudo if the "dmesg" section comes back empty.

sec() { printf '\n===== %s =====\n' "$1"; }

sec "date";            date -u
sec "kernel";          uname -r
sec "distro";          (. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")
sec "PipeWire";        pipewire --version 2>/dev/null | head -1
sec "WirePlumber";     wireplumber --version 2>/dev/null | head -1
sec "ALSA cards";      cat /proc/asound/cards 2>/dev/null
sec "PCI audio";       lspci -nnk 2>/dev/null | grep -A3 -iE 'audio|multimedia|acp' || true
sec "SoundWire devices"; ls /sys/bus/soundwire/devices/ 2>/dev/null || true
sec "aplay -l";        aplay -l 2>&1
sec "arecord -l";      arecord -l 2>&1
sec "dmesg: soundwire / tas2783 / acp / -22 errors"
  { journalctl -k -b 2>/dev/null || dmesg 2>/dev/null; } \
  | grep -iE 'soundwire|tas278|rt721|acp70|acp63|snd_acp|Program (params|transport)|ASoC error' \
  | tail -80
sec "wpctl status";    wpctl status 2>&1
sec "card mixer controls"
  amixer -c amdsoundwire controls 2>&1 | grep -iE 'tas2783|spk|amp|Spk' || true
sec "tas2783 amp gain"
  amixer -c amdsoundwire sget 'tas2783-1 Amp' 2>&1 | tail -3
  amixer -c amdsoundwire sget 'tas2783-2 Amp' 2>&1 | tail -3
sec "installed workaround files"
  ls -l "${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d/99-proart-px13-audio.conf" 2>&1
  ls -l "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tas2783-amp-cap.service" 2>&1
  systemctl --user is-enabled tas2783-amp-cap.service 2>&1
echo
