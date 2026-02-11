from mido import MidiFile, MidiTrack

INPUT_MIDI = "house.mid"
OUTPUT_MIDI = "output_merged.mid"

TARGET_CHANNEL = 0  # 0 = Channel 1 in MIDI terms
REMOVE_DRUMS = True  # removes channel 9 (MIDI channel 10)

mid = MidiFile(INPUT_MIDI)
out_mid = MidiFile(ticks_per_beat=mid.ticks_per_beat)

for track in mid.tracks:
    out_track = MidiTrack()
    out_mid.tracks.append(out_track)

    for msg in track:
        if msg.type in ("note_on", "note_off"):
            if REMOVE_DRUMS and msg.channel == 9:
                continue

            out_track.append(msg.copy(channel=TARGET_CHANNEL))
        else:
            # Preserve non-note events (tempo, program change, etc.)
            out_track.append(msg.copy())

out_mid.save(OUTPUT_MIDI)

print(f"Saved merged MIDI to: {OUTPUT_MIDI}")
