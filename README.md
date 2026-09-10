# ProArt PX13 (Strix Halo) — Linux audio fix

Get working sound on the **ASUS ProArt PX13 / PX13 Pro (HN7306)** — AMD
**Ryzen AI Max+ 395 "Strix Halo"** — under Linux, until the kernel driver
is fixed upstream.

> Tested on Bazzite 44 (kernel `7.2.3`), PipeWire 1.6, WirePlumber 0.5,
> September 2026. Distro-agnostic — anything with PipeWire + WirePlumber and
> a systemd **user** session (Fedora/Bazzite, Arch, openSUSE, Ubuntu 24.10+, …).
> `systemd-machined` is used for the resume hook (present by default on the
> distros above).

---

## Symptoms

- No audio devices, or only a **"Dummy Output"** in your sound settings.
- `wpctl status` shows the card but no usable sink.
- Sound works after a cold boot but **dies after every suspend / lid-close**,
  with `spa.alsa: hw:…p: snd_pcm_avail after recover: Broken pipe` in the
  PipeWire log.
- Kernel log fills with:
  ```
  soundwire sdw-master-0-1: Program params failed: -22
  SDW1-PIN4-CAPTURE-SmartAmp: ASoC error (-22): at snd_soc_link_prepare()
  ```

## Cause

The speakers, mics and headphone jack are on an **AMD ACP7.0 SoundWire**
bus: a **Realtek RT721** headset codec plus two **TI TAS2783 "SmartAmp"**
chips for the speakers. The kernel machine driver
`snd_acp_sdw_legacy_mach` fails to bring up the TAS2783 **IV-sense capture**
link (the speaker-protection feedback path). Because that one endpoint
fails, PipeWire marks the whole card profile *unavailable* and falls back
to a Dummy Output — so nothing plays.

Separately, the mainline `snd_soc_tas2783_sdw` driver here has **no
SmartAmp DSP** — no cone-excursion limiter, no voice-coil thermal model.
The amp chip's silicon safeguards (over-temp, over-current, DC/short, UVLO)
still protect the *amplifier*, but nothing limits mechanical/thermal
over-drive of the small *speakers*.

## What this repo does

Two pieces are **user-scoped** (no root, no reboot); a third is a small
root-owned systemd unit for the suspend/resume case, because a
`systemd --user` unit cannot hook `suspend.target`.

| Piece | Effect |
| --- | --- |
| `99-proart-px13-audio.conf` (WirePlumber drop-in) | Pins the card to the `pro-audio` profile so the working PCMs are exposed; names the nodes (`Speakers`, `Headphones`, `Built-in Microphone`, `Headset Microphone`); makes `Speakers` the default output; disables the dead IV-sense capture PCM so it stops spamming `-22` in the kernel log. |
| `tas2783-amp-cap.service` (systemd **user** unit) | Caps the TAS2783 **analog** gain from +21 dB to **+16 dB** (a 5 dB cut) at every login — a conservative stand-in for the missing DSP protection. Applies to every audio path. |
| `proart-audio-resume.service` (systemd **system** unit) | On resume from suspend/hibernate, restarts `wireplumber pipewire pipewire-pulse` in the user session and re-applies the gain cap. Without it the speaker PCM comes back wedged in a `-EPIPE` / "Broken pipe" state and there is no sound until you restart the audio stack by hand. `install.sh` bakes your username / UID into it. |

### Trade-offs

- **No headphone-jack auto-switching.** `Speakers` and `Headphones` appear
  as separate outputs; switch manually when you plug/unplug.
- **Speaker protection is static, not adaptive.** Keep the volume moderate
  with bass-heavy content (deep-bass music, movie LFE, test tones) and
  don't sit at 100% for long stretches. Tune the cap lower if you want
  more margin (see below).
- **The resume hook is a blunt restart.** It bounces the whole user audio
  stack on every resume, so anything that was playing is interrupted for
  ~1 s and apps may need to re-open their stream.

## Install

```sh
git clone https://github.com/raaven-nest/proart-px13-strixhalo-audio-fix.git
cd proart-px13-strixhalo-audio-fix
./install.sh
```

`install.sh` runs unprivileged for the two user-scoped pieces, then calls
`sudo` once to install and enable `proart-audio-resume.service`. If `sudo`
is unavailable it skips that step with a warning — everything except
suspend/resume recovery still works.

Log out and back in (or reboot) if sound doesn't come up immediately.

## Verify

```sh
wpctl status | sed -n '/Sinks:/,/Filters:/p'          # -> Speakers, Headphones
amixer -c amdsoundwire sget 'tas2783-1 Amp' | tail -1  # -> [16.00dB]
systemctl --user is-enabled tas2783-amp-cap.service    # -> enabled
systemctl is-enabled proart-audio-resume.service       # -> enabled
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1      # brief tone
```

To test the resume path without a real suspend cycle:

```sh
sudo systemctl start proart-audio-resume.service       # should restart the stack cleanly
sudo systemctl suspend                                  # then resume and confirm sound still works
```

## Tune the gain cap

Analog gain range is `0..20` → +11.0 dB … +21.0 dB (0.5 dB/step). Default
here is `10` (+16 dB).

```sh
systemctl --user edit tas2783-amp-cap.service
```
```ini
[Service]
Environment=AMP_GAIN=8
```
```sh
systemctl --user restart tas2783-amp-cap.service
```

## Uninstall

```sh
./uninstall.sh
```
Restores the amp gain, removes the WirePlumber drop-in and both systemd
units (using `sudo` for the system one), and clears the saved profile
choice. The kernel bug is still there afterwards, so expect the Dummy
Output to return until a fixed kernel ships.

## When is this no longer needed?

Re-test after each kernel bump. You're fixed upstream when, **without** this
workaround:

- a real `Speakers` / `Analog Stereo` card profile appears (not just
  `pro-audio` / `off`), **and/or**
- the `Program params failed: -22` / `ASoC error (-22)` lines stop, **and**
- sound survives a suspend/resume cycle without a `snd_pcm_avail … Broken
  pipe` in the PipeWire log.

At that point run `./uninstall.sh`.

## Contributing

PRs and issues welcome — especially if your unit enumerates the capture
PCMs in a different order (the `pro-input-3` / `pro-input-1` / `pro-input-4`
numbers in the WirePlumber file). Run `./diagnose.sh` and attach the
output.

Upstream is the right place for the actual fix: the `linux-sound` list
(<https://lore.kernel.org/linux-sound/>), the ALSA project, and the
SOF / `soundwire` maintainers.

## License

[CC0 1.0 Universal](LICENSE) — public domain. Do whatever you want; no
attribution required.

## Disclaimer

Provided as-is. The gain cap is a mitigation, not a guarantee — you are
responsible for your own hardware and listening levels.
