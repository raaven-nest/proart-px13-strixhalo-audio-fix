#!/usr/bin/env bash
# Install the ProArt PX13 (Strix Halo) audio workaround.
# Everything is user-scoped: no root, no system files, no reboot required.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
WP_DST="$CFG/wireplumber/wireplumber.conf.d"
SD_DST="$CFG/systemd/user"

echo "==> Checking hardware..."
if ! grep -qi 'amd-soundwire' /proc/asound/cards 2>/dev/null; then
  echo "!! No 'amd-soundwire' ALSA card found."
  echo "   This workaround is for the ASUS ProArt PX13 (Ryzen AI Max+ 395 / Strix Halo)."
  echo "   Run ./diagnose.sh and open an issue if you believe this check is wrong."
  exit 1
fi
echo "   OK: amd-soundwire card present."

echo "==> Installing WirePlumber drop-in -> $WP_DST/"
mkdir -p "$WP_DST"
install -m 0644 "$SRC/config/wireplumber/99-proart-px13-audio.conf" "$WP_DST/99-proart-px13-audio.conf"

echo "==> Installing systemd user unit -> $SD_DST/"
mkdir -p "$SD_DST"
install -m 0644 "$SRC/config/systemd/tas2783-amp-cap.service" "$SD_DST/tas2783-amp-cap.service"

echo "==> Enabling tas2783-amp-cap.service"
systemctl --user daemon-reload
systemctl --user enable --now tas2783-amp-cap.service

echo "==> Restarting the audio stack"
systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null \
  || systemctl --user restart wireplumber pipewire
sleep 3

echo
echo "==> Result:"
wpctl status 2>/dev/null | sed -n '/Sinks:/,/Filters:/p' || true
amixer -c amdsoundwire sget 'tas2783-1 Amp' 2>/dev/null | tail -1 || true
echo
echo "Done. If there is still no sound, log out and back in (or reboot) and re-check."
echo "Pick the 'Speakers' / 'Headphones' output manually in your sound settings;"
echo "there is no headphone-jack auto-switching in this mode."
