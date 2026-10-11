# FRAGLINE: stub replacing the upstream 800 KB Shift JIS table (Kanji mode is never used here;
# the game only encodes ASCII join links in byte mode). Same API, ASCII passthrough only.
extends RefCounted

static func to_shift_jis_2004_buffer(text: String) -> PackedByteArray:
    return text.to_ascii_buffer()

static func get_string_from_shift_jis_2004(arr: PackedByteArray) -> String:
    return arr.get_string_from_ascii()
