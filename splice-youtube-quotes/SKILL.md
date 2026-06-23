---
name: splice-youtube-quotes
description: Download a short YouTube video, split its audio into individual alert WAV clips, stage them under ~/alerts/tmp, and prepare final slugged alert filenames. Use when Codex is given a YouTube URL and asked to create alert sounds or quote clips for the alerts folder.
---

# Extract YouTube Alerts

Use this when the user gives a YouTube URL and wants short quote or alert WAVs staged for review.

## Rules

- Stage work under `/Users/kevin/alerts/tmp/<slug>/`.
- Keep `source.wav`, `waveform.png`, and `cuts.tsv` in the staging folder.
- Do not move files into `/Users/kevin/alerts/` or edit alert YAML files until the user signs off on the staged clips.
- Always cut from `source.wav`; do not repeatedly cut already-cut clips.
- If the user gives a quote count, use it as a hard constraint for the draft clip count.
- Before exporting any clips, propose the timestamp boundaries you intend to splice, ask the user to confirm or correct the total quote count, and wait for explicit sign-off. Do not splice until the user approves the proposed cuts.
- If labels are unknown, ask the user for the quote text in order. Codex cannot reliably transcribe audio natively; try captions or a local transcription tool only if available and worth the time.

## Workflow

1. Create a staging folder:

   ```bash
   mkdir -p /Users/kevin/alerts/tmp/<slug>
   ```

2. Download audio from the YouTube URL:

   ```bash
   yt-dlp --no-playlist -x --audio-format wav --audio-quality 0 \
     -o '/Users/kevin/alerts/tmp/<slug>/source.%(ext)s' '<youtube-url>'
   ```

3. Confirm duration:

   ```bash
   ffprobe -v error -show_entries format=duration \
     -of default=noprint_wrappers=1:nokey=1 \
     /Users/kevin/alerts/tmp/<slug>/source.wav
   ```

4. Generate a waveform image:

   ```bash
   ffmpeg -y -hide_banner -i /Users/kevin/alerts/tmp/<slug>/source.wav \
     -filter_complex 'showwavespic=s=3600x700:colors=0x2f6fff' \
     -frames:v 1 /Users/kevin/alerts/tmp/<slug>/waveform.png
   ```

5. Run silence detection at a few thresholds:

   ```bash
   ffmpeg -hide_banner -i /Users/kevin/alerts/tmp/<slug>/source.wav \
     -af silencedetect=n=-35dB:d=0.12 -f null -
   ffmpeg -hide_banner -i /Users/kevin/alerts/tmp/<slug>/source.wav \
     -af silencedetect=n=-30dB:d=0.12 -f null -
   ffmpeg -hide_banner -i /Users/kevin/alerts/tmp/<slug>/source.wav \
     -af silencedetect=n=-40dB:d=0.12 -f null -
   ```

6. If separators are not true silence, compute RMS valleys with Python stdlib:

   ```bash
   python3 - <<'PY'
   import math, struct, wave
   from pathlib import Path

   path = Path('/Users/kevin/alerts/tmp/<slug>/source.wav')
   with wave.open(str(path), 'rb') as w:
       channels = w.getnchannels()
       rate = w.getframerate()
       frames = w.getnframes()
       width = w.getsampwidth()
       data = w.readframes(frames)

   if width != 2:
       raise SystemExit(f'unexpected sample width: {width}')

   win = int(rate * 0.02)
   rms = []
   for start in range(0, frames, win):
       count_frames = min(win, frames - start)
       offset = start * channels * width
       chunk = data[offset : offset + count_frames * channels * width]
       total = 0
       count = 0
       for (sample,) in struct.iter_unpack('<h', chunk):
           total += sample * sample
           count += 1
       rms.append(math.sqrt(total / count) / 32768 if count else 0)

   smoothed = []
   for i in range(len(rms)):
       lo = max(0, i - 3)
       hi = min(len(rms), i + 4)
       smoothed.append(sum(rms[lo:hi]) / (hi - lo))

   minima = []
   neighborhood = int(0.12 / 0.02)
   margin = int(0.25 / 0.02)
   for i in range(margin, len(smoothed) - margin):
       lo = max(0, i - neighborhood)
       hi = min(len(smoothed), i + neighborhood + 1)
       if smoothed[i] == min(smoothed[lo:hi]):
           t = (i + 0.5) * 0.02
           if minima and t - minima[-1][0] < 0.18:
               if smoothed[i] < minima[-1][1]:
                   minima[-1] = (t, smoothed[i])
           else:
               minima.append((t, smoothed[i]))

   for t, energy in sorted(minima, key=lambda item: item[1])[:60]:
       print(f'{t:7.3f} {energy:.5f}')
   PY
   ```

7. Choose draft cut boundaries from the waveform plus valley list. If the user gave `N` quotes, choose `N + 1` timestamps including start and end. Before exporting files, report the proposed timestamp list, your best-guess quote count, and ask the user to confirm the total quote count and approve or correct the splice points.

8. After the user signs off on the timestamp list, export draft clips from the original source:

   ```bash
   ffmpeg -y -hide_banner -loglevel error \
     -ss <start> -to <end> \
     -i /Users/kevin/alerts/tmp/<slug>/source.wav \
     -ac 2 -ar 48000 \
     /Users/kevin/alerts/tmp/<slug>/<draft-or-final-name>.wav
   ```

9. Write `cuts.tsv` with:

   ```text
   file    start    end    duration    text
   ```

   Get each duration from `ffprobe` on the generated file.

10. Ask the user to review the staged WAVs. Expect corrections like:

   - combine adjacent clips
   - split one clip at a percentage or timestamp
   - move a boundary earlier or later because the tail of one quote is in the next clip
   - rename from quote text

11. Apply corrections by regenerating only affected files from `source.wav`, then update `cuts.tsv`.

12. When labels are approved, slugify filenames:

   ```text
   <speaker-prefix>-<lowercase-quote-with-dashes>.wav
   ```

13. Keep final review files directly in `/Users/kevin/alerts/tmp/<slug>/`. Remove intermediate folders only after the final named files are present.

## Practical Notes

- Some videos use low-energy separators rather than true silence; in that case, `silencedetect` may miss most quote breaks.
- A full waveform gives orientation, but zoomed waveform panels can be useful for tight split corrections.
- If a split is wrong, move the boundary and regenerate both adjacent files from `source.wav`.
- Prefer explicit shell variables/functions over clever tab-delimited shell parsing when rebuilding `cuts.tsv`.
- Keep all work in staging until the user approves the final files and names.
