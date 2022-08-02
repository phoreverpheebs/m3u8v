module m3u8

import os
import regex

/*
protocol versions:
	3: Floating-point EXTINF duration values

	4: EXT-X-BYTERANGE, EXT-X-I-FRAME-STREAM-INF, EXT-X-I-FRAMES-ONLY,
		EXT-X-MEDIA, the AUDIO and VIDEO attributes of the EXT-X-STREAM-INF tag

	5: KEYFORMAT and KEYFORMATVERSIONS attributes of the EXT-X-KEY tag.
		The EXT-X-MAP tag. SUBTITLES media type. SAMPLE-AES encryption method EXT-X-KEY

	6: CLOSED-CAPTIONS media type. Allow EXT-X-MAP for subtitle playlists

	7: EXT-X-SESSION-DATA, EXT-X-SESSION-KEY, EXT-X-DATERANGE, 'SERVICEn' values of
		INSTREAM-ID, AVERAGE-BANDWIDTH, FRAME-RATE, CHANNELS, and HDCP-LEVEL attributes.

	8: EXT-X-GAP, EXT-X-DEFINE, Variable Substitution, VIDEO-RANGE attribute.
*/

const regex_query = r'([a-zA-Z0-9_\-]+)=(("(?:[^"]|[^",])+")|([^,]+))'

pub fn decode_from_file(path string, strict bool) ?(Playlist, PlaylistType) {
	return decode(os.read_file(path)?, strict)
}

pub fn decode(data string, strict bool) ?(Playlist, PlaylistType) {
	return decode_m3u8(&data, strict)
}

[direct_array_access]
fn decode_m3u8(data &string, strict bool) ?(Playlist, PlaylistType) {
	mut wv := Widevine{}

	mut state := DecodeState{}

	mut master := new_master_playlist()
	mut media := new_media_playlist(1024)

	for _, line in data.split_into_lines() {
		if line.len < 1 || line == '\r' {
			continue
		}

		decode_line_of_master(mut master, mut state, line, strict) or {
			if strict {
				return err
			}
		}

		decode_line_of_media(mut media, mut wv, mut state, line, strict) or {
			if strict {
				return err
			}
		}
	}

	if state.list_type == .media && state.widevine {
		media.widevine = wv
	}

	if strict && !state.m3u {
		return error('m3u8: Unable to find #EXTM3U tag')
	}

	match state.list_type {
		.@none { return error('m3u8: Unknown playlist type') }
		.master { return master, PlaylistType.master }
		.media { return media, PlaylistType.media }
	}

	return none
}

pub fn decode_attribute_list(list string) map[string]string {
	return decode_params(list)
}

fn decode_params(raw_line string) map[string]string {
	mut line := raw_line
	if !line.ends_with(',') {
		line += ','
	}
	mut out := map[string]string{}
	mut re := regex.regex_opt(regex_query) or { panic(err) }
	for _, v in re.find_all_str(line) {
		attr := v.split('=')
		if attr.len < 2 {
			continue
		}
		out[attr[0]] = attr[1].trim(' "')
	}

	return out
}

fn set_newer_version(current_version u8, newer_version u8) u8 {
	if current_version < newer_version {
		return newer_version
	}
	return current_version
}