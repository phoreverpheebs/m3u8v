module m3u8

import math
import strconv
import time

// `MediaPlaylist` is the media playlist type containing various segments
pub struct MediaPlaylist {
pub mut:
	segments               []MediaSegment 	// segments
	media_type             MediaType		// VOD or EVENT
	media_sequence         u64
	discontinuity_sequence u64
	//
	time_offset        f64
	precise_start_time bool
	target_duration    f64
	//
	allow_cache			 bool
	closed               bool
	iframe               bool
	independent_segments bool
	//
	widevine Widevine
	map      Map
	key      Key
	//
	args   string
	custom map[string]CustomTag
mut:
	capacity u32 // == playlist.segments.len
	version  u8 = 3
	head     u32
	tail     u32
	count    u32
}

// `new_media_playlist` creates a new media playlist
pub fn new_media_playlist(capacity u32) MediaPlaylist {
	mut playlist := MediaPlaylist{
		capacity: capacity
	}
	playlist.segments = []MediaSegment{len: int(capacity)}
	return playlist
}

// `decode_media_playlist` decodes data into a media playlist
// useful for when you know a playlist is of type media
// `strict` will return syntax errors if true
// capacity is the media playlists capacity, 1024 is default if capacity is less than 1
pub fn decode_media_playlist(data string, capacity u32, strict bool) ?MediaPlaylist {
	mut cap := capacity
	if cap <= 0 {
		cap = 1024
	}
	mut state := DecodeState{}
	mut wv := Widevine{}
	mut playlist := new_media_playlist(cap)

	for _, line in data.split_into_lines() {
		if line.len < 1 || line == '\r' {
			continue
		}

		decode_line_of_media(mut playlist, mut wv, mut state, line, strict) or {
			if strict {
				return err
			}
		}
	}

	if state.widevine {
		playlist.widevine = wv
	}

	if strict && !state.m3u {
		return error('m3u8: Unable to find #EXTM3U tag')
	}

	return playlist
}

[direct_array_access]
fn decode_line_of_media(mut playlist MediaPlaylist, mut wv Widevine, mut state DecodeState, raw_line string, strict bool) ? {
	mut line := raw_line.trim_space()

	match true {
		// EXTINF
		line.starts_with('#EXTINF:') && !state.inf {
			state.inf = true
			state.list_type = .media
			seperator_index := line.index(',') or {
				if strict {
					return error('m3u8: Unable to parse line: $line')
				}
				line.len
			}
			duration := line[8..seperator_index]
			if duration.len > 0 {
				state.duration = strconv.atof64(duration) or {
					if strict {
						return error('m3u8: Unable to parse duration: $err')
					}
					0
				}
			}
			if line.len > seperator_index {
				state.title = line[seperator_index + 1..]
			}
		}
		line.starts_with('#EXT-X-BITRATE:') {
			state.list_type = .media
			state.bitrate = strconv.parse_int(line.all_after('#EXT-X-BITRATE:'), 10, 64) or {
				if strict {
					return error('m3u8: Unable to parse bitrate: $err')
				}
				0
			}
			state.bitrate_done = true
		}
		!line.starts_with('#') {
			if state.inf {
				playlist.append(state.title, line, state.duration) or {
					if err == error('Playlist is full') {
						playlist.segments << []MediaSegment{len: int(playlist.count())}
						playlist.capacity = u32(playlist.segments.len)
						playlist.tail = playlist.count
						playlist.append(state.title, line, state.duration) or {
							return error('m3u8: Unable to append segment to playlist: $err')
						}
					} else {
						return error('m3u8: Unable to append segment to playlist: $err')
					}
					state.inf = false
				}
			}
			if state.range {
				state.range = false
				playlist.set_range(state.limit, state.offset) or {
					if strict {
						return error('m3u8: Unable to set range of segment: $err')
					}
				}
			}
			if state.scte35 {
				state.scte35 = false
				playlist.set_scte35(state.scte) or {
					if strict {
						return error('m3u8: Unable to set SCTE-35: $err')
					}
				}
			}
			if state.discontinuity {
				state.discontinuity = false
				playlist.set_discontinuity() or {
					if strict {
						return error('m3u8: Unable to set discontinuity: $err')
					}
				}
			}
			if state.program_date_time_done && playlist.count() > 0 {
				state.program_date_time_done = false
				playlist.set_program_date_time(state.program_date_time) or {
					if strict {
						return error('m3u8: Unable to set program datetime: $err')
					}
				}
			}
			if state.key {
				playlist.segments[playlist.last_segment()].key = Key{
					...state.x_key
				}
				if isnil(playlist.key) {
					playlist.key = state.x_key
				}
				state.key = false
			}
			if state.map {
				playlist.segments[playlist.last_segment()].map = Map{
					...state.x_map
				}
				if !isnil(playlist.map) {
					playlist.map = state.x_map
				}
				state.map = false
			}
			if state.custom {
				playlist.segments[playlist.last_segment()].custom_tags = state.custom_map.move()
				state.custom_map = map[string]CustomTag{}
				state.custom = false
			}
			if state.bitrate_done {
				state.bitrate_done = false
				playlist.set_bitrate(state.bitrate) or {
					if strict {
						return error('m3u8: Unable to set bitrate: $err')
					}
				}
			}
		}
		line == '#EXTM3U' {
			state.m3u = true
		}
		line == '#EXT-X-ENDLIST' {
			state.list_type = .media
			playlist.closed = true
		}
		line.starts_with('#EXT-X-VERSION:') {
			state.list_type = .media
			playlist.version = u8(strconv.atoi(line.all_after('#EXT-X-VERSION:')) or {
				if strict {
					return error('m3u8: Unable to parse playlist version: $err')
				}
				3
			})
		}
		line.starts_with('#EXT-X-TARGETDURATION:') {
			state.list_type = .media
			playlist.target_duration = strconv.atof64(line.all_after('#EXT-X-TARGETDURATION:')) or {
				if strict {
					return error('m3u8: Unable to parse playlist target duration: $err')
				}
				0.0
			}
		}
		line.starts_with('#EXT-X-MEDIA-SEQUENCE:') {
			state.list_type = .media
			playlist.media_sequence = strconv.parse_uint(line.all_after('#EXT-X-MEDIA-SEQUENCE:'),
				10, 64) or {
				if strict {
					return error('m3u8: Unable to parse media sequence number: $err')
				}
				0
			}
		}
		line.starts_with('#EXT-X-ALLOW-CACHE:') {
			state.list_type = .media
			match line.all_after('#EXT-X-ALLOW-CACHE:') {
				'YES' {
					playlist.allow_cache = true
					if playlist.version == 7 && strict {
						return error('m3u8: #EXT-X-ALLOW-CACHE was removed in protocol version 7')
					}
				}
				else {}
			}
		}
		line.starts_with('#EXT-X-PLAYLIST-TYPE:') {
			state.list_type = .media
			media_playlist_type := line.all_after('#EXT-X-PLAYLIST-TYPE:')

			match media_playlist_type {
				'EVENT' { playlist.media_type = .event }
				'VOD' { playlist.media_type = .vod }
				else { playlist.media_type = .@none }
			}
		}
		line.starts_with('#EXT-X-DISCONTINUITY-SEQUENCE:') {
			state.list_type = .media
			playlist.discontinuity_sequence = strconv.parse_uint(line.all_after('#EXT-X-DISCONTINUITY-SEQUENCE:'),
				10, 64) or {
				if strict {
					return error('m3u8: Unable to parse discontinuity sequence number: $err')
				}
				0
			}
		}
		line.starts_with('#EXT-X-START:') {
			state.list_type = .media
			for k, v in decode_params(line.all_after('#EXT-X-START:')) {
				match k {
					'TIME-OFFSET' {
						start_time := strconv.atof64(v) or {
							if strict {
								return error('m3u8: Unable to parse time offset: $err')
							}
							0.0
						}
						playlist.time_offset = start_time
					}
					'PRECISE' {
						playlist.precise_start_time = v == 'YES'
					}
					else {}
				}
			}
		}
		line.starts_with('#EXT-X-KEY:') {
			state.list_type = .media
			state.x_key = Key{}
			for k, v in decode_params(line.all_after('#EXT-X-KEY:')) {
				match k {
					'METHOD' { state.x_key.method = match v {
						'AES-128' { .aes_128 }
						'SAMPLE-AES' { .sample_aes }
						else { .@none }
					} }
					'URI' { state.x_key.uri = v }
					'IV' { state.x_key.iv = v }
					'KEYFORMAT' { state.x_key.keyformat = v }
					'KEYFORMATVERSIONS' { state.x_key.keyformatversions = v }
					else {}
				}
			}
			state.key = true
		}
		line.starts_with('#EXT-X-MAP:') {
			state.list_type = .media
			state.x_map = &Map{}
			playlist.version = set_newer_version(playlist.version, 5)
			for k, v in decode_params(line.all_after('#EXT-X-MAP:')) {
				match k {
					'URI' {
						state.x_map.uri = v
					}
					'BYTERANGE' {
						state.x_map.limit = strconv.parse_int(line.all_before('@'), 10,
							64) or {
							if strict {
								return error('m3u8: Unable to parse limit from byte-range: $err')
							}
							0
						}
						state.x_map.offset = strconv.parse_int(line.all_after('@'), 10,
							64) or {
							if strict {
								return error('m3u8: Unable to parse offset from byte-range: $err')
							}
							0
						}
					}
					else {}
				}
			}
			state.map = true
		}
		line.starts_with('#EXT-X-PROGRAM-DATE-TIME:') && !state.program_date_time_done {
			state.program_date_time_done = true
			state.list_type = .media
			if strict {
				state.program_date_time = time.parse_rfc3339(line.all_after('#EXT-X-PROGRAM-DATE-TIME:')) or {
					if strict {
						return error('m3u8: Unable to parse program date time in rfc3339 format: $err')
					}
					time.Time{}
				}
			} else {
				state.program_date_time = time.parse_iso8601(line.all_after('#EXT-X-PROGRAM-DATE-TIME:')) or {
					if strict {
						return error('m3u8: Unable to parse program date time in iso8601 format: $err')
					}
					time.Time{}
				}
			}
		}
		line.starts_with('#EXT-X-BYTERANGE:') && !state.range {
			state.range = true
			state.list_type = .media
			state.offset = 0
			playlist.version = set_newer_version(playlist.version, 4)
			parameters := line.all_after('#EXT-X-BYTERANGE:').split_nth('@', 2)

			state.limit = strconv.parse_int(parameters[0], 10, 64) or {
				if strict {
					return error('m3u8: Unable to parse limit from byte-range: $err')
				}
				0
			}
			if parameters.len > 1 {
				state.offset = strconv.parse_int(parameters[1], 10, 64) or {
					if strict {
						return error('m3u8: Unable to parse offset from byte-range: $err')
					}
					0
				}
			}
		}
		line.starts_with('#EXT-SCTE35:') && !state.scte35 {
			state.scte35 = true
			state.list_type = .media
			state.scte = SCTE{
				syntax: .scte_67_2014
			}
			for attr, val in decode_params(line.all_after('#EXT-SCTE35:')) {
				match attr {
					'CUE' { state.scte.cue = val }
					'ID' { state.scte.id = val }
					'TIME' { state.scte.time = val.f64() }
					else {}
				}
			}
		}
		line.starts_with('#EXT-OATCLS-SCTE35:') && !state.scte35 {
			state.scte35 = true
			state.scte = SCTE{
				syntax: .oatcls
				cue: line.all_after('#EXT-OATCLS-SCTE35:')
			}
		}
		line.starts_with('#EXT-X-CUE-OUT:') && state.scte35 && state.scte.syntax == .oatcls {
			state.scte.time = line.all_after('#EXT-X-CUE-OUT:').f64()
			state.scte.cue_type = .cue_start
		}
		line.starts_with('#EXT-X-CUE-OUT-CONT:') && !state.scte35 {
			state.scte35 = true
			state.scte = SCTE{
				syntax: .oatcls
				cue_type: .cue_mid
			}
			for attr, val in decode_params(line.all_after('#EXT-X-CUE-OUT-CONT:')) {
				match attr {
					'SCTE35' { state.scte.cue = val }
					'Duration' { state.scte.time = val.f64() }
					'ElapsedTime' { state.scte.elapsed = val.f64() }
					else {}
				}
			}
		}
		line == '#EXT-X-CUE-IN' && !state.scte35 {
			state.scte35 = true
			state.scte = &SCTE{
				syntax: .oatcls
				cue_type: .cue_end
			}
		}
		line.starts_with('#EXT-X-DISCONTINUITY') && !state.discontinuity {
			state.discontinuity = true
			state.list_type = .media
		}
		line.starts_with('#EXT-X-I-FRAMES-ONLY') {
			playlist.iframe = true
			state.list_type = .media
		}
		line.starts_with('#EXT-X-INDEPENDENT-SEGMENTS') {
			playlist.independent_segments = true
		}
		line.starts_with('#WV-') {
			mut wv_line := line.all_after('#WV-')
			state.list_type = .media
			mut error_occured := false
			match true {
				wv_line.starts_with('AUDIO-CHANNELS') {
					channels := strconv.parse_uint(wv_line.all_after('AUDIO-CHANNELS '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine audio channel count: $err')
						}
						error_occured = true
						0
					}
					wv.audio_channels = u32(channels)
				}
				wv_line.starts_with('AUDIO-FORMAT') {
					format := strconv.parse_uint(wv_line.all_after('AUDIO-FORMAT '), 10,
						32) or {
						if strict {
							return error('m3u8: Unable to parse  widevine audio format: $err')
						}
						error_occured = true
						0
					}
					wv.audio_format = u32(format)
				}
				wv_line.starts_with('AUDIO-PROFILE-IDC') {
					profile := strconv.parse_uint(wv_line.all_after('AUDIO-PROFILE-IDC '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine audio profile: $err')
						}
						error_occured = true
						0
					}
					wv.audio_profile_idc = u32(profile)
				}
				wv_line.starts_with('AUDIO-SAMPLE-SIZE') {
					sample_size := strconv.parse_uint(wv_line.all_after('AUDIO-SAMPLE-SIZE '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine audio sample size: $err')
						}
						error_occured = true
						0
					}
					wv.audio_sample_size = u32(sample_size)
				}
				wv_line.starts_with('AUDIO-SAMPLING-FREQUENCY') {
					sampling_frequency := strconv.parse_uint(wv_line.all_after('AUDIO-SAMPLING-FREQUENCY '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine audio sampling frequency: $err')
						}
						error_occured = true
						0
					}
					wv.audio_sample_frequency = u32(sampling_frequency)
				}
				wv_line.starts_with('CYPHER-VERSION') {
					wv.cypher_version = wv_line.all_after('CYPHER-VERSION ')
				}
				wv_line.starts_with('ECM') {
					wv.ecm = wv_line.all_after('ECM ')
				}
				wv_line.starts_with('VIDEO-FORMAT') {
					video_format := strconv.parse_uint(wv_line.all_after('VIDEO-FORMAT '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine video format: $err')
						}
						error_occured = true
						0
					}
					wv.video_format = u32(video_format)
				}
				// might be f64 ?
				wv_line.starts_with('VIDEO-FRAME-RATE') {
					frame_rate := strconv.parse_uint(wv_line.all_after('VIDEO-FRAME-RATE '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine video frame rate: $err')
						}
						error_occured = true
						0
					}
					wv.video_frame_rate = u32(frame_rate)
				}
				wv_line.starts_with('VIDEO-LEVEL-IDC') {
					level := strconv.parse_uint(wv_line.all_after('VIDEO-LEVEL-IDC '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine video level idc: $err')
						}
						error_occured = true
						0
					}
					wv.video_level_idc = u32(level)
				}
				wv_line.starts_with('VIDEO-PROFILE-IDC') {
					profile := strconv.parse_uint(wv_line.all_after('VIDEO-PROFILE-IDC '),
						10, 32) or {
						if strict {
							return error('m3u8: Unable to parse widevine video profile idc: $err')
						}
						error_occured = true
						0
					}
					wv.video_profile_idc = u32(profile)
				}
				wv_line.starts_with('VIDEO-RESOLUTION') {
					res := wv_line.all_after('VIDEO-RESOLUTION ').split('x')
					if res.len < 2 {
						if strict {
							return error('m3u8: Unable to parse widevine video resolution')
						}
					} else {
						width := strconv.parse_int(res[0], 10, 64) or {
							if strict {
								return error('m3u8: Unable to parse widevine video resolution width: $err')
							}
							0
						}
						height := strconv.parse_int(res[1], 10, 64) or {
							if strict {
								return error('m3u8: Unable to parse widevine video resolution height: $err')
							}
							0
						}
						wv.video_resolution = Resolution{
							width: width
							height: height
						}
					}
				}
				wv_line.starts_with('VIDEO-SAR') {
					wv.video_sar = wv_line.all_after('VIDEO-SAR ')
				}
				else {}
			}

			if !error_occured {
				state.widevine = true
			}
		}
		else {}
	}

	return
}

// `encode` returns playlist encoded as an m3u8 playlist file
[direct_array_access]
pub fn (playlist MediaPlaylist) encode() string {
	mut version := playlist.version
	mut buffer := ''

	if playlist.key != Key{} {
		buffer += '#EXT-X-KEY:METHOD=${playlist.key.method.str()}'
		if playlist.key.method != .@none {
			buffer += ',URI="${playlist.key.uri}"'
			if playlist.key.iv != '' {
				buffer += ',IV=${playlist.key.iv}'
			}
			if playlist.key.keyformat != '' {
				version = set_newer_version(version, 5)
				buffer += ',KEYFORMAT="${playlist.key.keyformat}"'
			}
			if playlist.key.keyformatversions != '' {
				version =  set_newer_version(version, 5)
				buffer += ',KEYFORMATVERSIONS="${playlist.key.keyformatversions}"'
			}
		}
		buffer += '\n'
	}

	if playlist.map != Map{} {
		version = set_newer_version(version, 5)
		buffer += '#EXT-X-MAP:URI="${playlist.map.uri}"'
		if playlist.map.limit > 0 {
			buffer += ',BYTERANGE=${playlist.map.limit}@${playlist.map.offset}'
		}
		buffer += '\n'
	}

	if playlist.media_type != .@none {
		buffer += '#EXT-X-PLAYLIST-TYPE:${playlist.media_type.str()}\n'
	}

	if playlist.allow_cache {
		buffer += '#EXT-X-ALLOW-CACHE:YES\n'
	}

	buffer += '#EXT-X-MEDIA-SEQUENCE:${playlist.media_sequence}\n#EXT-X-TARGETDURATION:${i64(math.ceil(playlist.target_duration))}\n'

	if playlist.time_offset > 0.0 {
		buffer += '#EXT-X-START:TIME-OFFSET=${playlist.time_offset}'
		if playlist.precise_start_time {
			buffer += ',PRECISE=YES'
		}
		buffer += '\n'
	}
	if playlist.discontinuity_sequence != 0 {
		buffer += '#EXT-X-DISCONTINUITY-SEQUENCE:${playlist.discontinuity_sequence}\n'
	}
	if playlist.iframe {
		buffer += '#EXT-X-I-FRAMES-ONLY\n'
	}
	if playlist.widevine != Widevine{} {
		if playlist.widevine.audio_channels != 0 {
			buffer += '#WV-AUDIO-CHANNELS ${playlist.widevine.audio_channels}\n'
		}
		if playlist.widevine.audio_format != 0 {
			buffer += '#WV-AUDIO-FORMAT ${playlist.widevine.audio_format}\n'
		}
		if playlist.widevine.audio_profile_idc != 0 {
			buffer += '#WV-AUDIO-PROFILE-IDC ${playlist.widevine.audio_profile_idc}\n'
		}
		if playlist.widevine.audio_sample_size != 0 {
			buffer += '#WV-AUDIO-SAMPLE-SIZE ${playlist.widevine.audio_sample_size}\n'
		}
		if playlist.widevine.audio_sample_frequency != 0 {
			buffer += '#WV-AUDIO-SAMPLING-FREQUENCY ${playlist.widevine.audio_sample_frequency}\n'
		}
		if playlist.widevine.cypher_version != '' {
			buffer += '#WV-CYPHER-VERSION ${playlist.widevine.cypher_version}\n'
		}
		if playlist.widevine.ecm != '' {
			buffer += '#WV-ECM ${playlist.widevine.ecm}\n'
		}
		if playlist.widevine.video_format != 0 {
			buffer += '#WV-VIDEO-FORMAT ${playlist.widevine.video_format}'
		}
		if playlist.widevine.video_frame_rate != 0 {
			buffer += '#WV-VIDEO-FRAME-RATE ${playlist.widevine.video_frame_rate}\n'
		}
		if playlist.widevine.video_level_idc != 0 {
			buffer += '#WV-VIDEO-LEVEL-IDC ${playlist.widevine.video_level_idc}\n'
		}
		if playlist.widevine.video_profile_idc != 0 {
			buffer += '#WV-VIDEO-PROFILE-IDC ${playlist.widevine.video_profile_idc}\n'
		}
		if playlist.widevine.video_resolution.width != 0 && playlist.widevine.video_resolution.height != 0 {
			buffer += '#WV-VIDEO-RESOLUTION ${playlist.widevine.video_resolution}\n'
		}
		if playlist.widevine.video_sar != '' {
			buffer += '#WV-VIDEO-SAR ${playlist.widevine.video_sar}\n'
		}
	}

	mut segment := MediaSegment{}
	mut cache := map[f64]string{}

	mut head := playlist.head
	mut count := playlist.count
	for _ = u32(0); count > 0; count-- {
		segment = playlist.segments[head]
		head = (head + 1) % playlist.capacity
		if segment == MediaSegment{} {
			continue
		}

		if segment.scte != SCTE{} {
			match segment.scte.syntax {
				.scte_67_2014 {
					buffer += '#EXT-SCTE35:CUE="${segment.scte.cue}"'
					if segment.scte.id != '' {
						buffer += ',ID="${segment.scte.id}"'
					}
					if segment.scte.time != 0.0 {
						buffer += ',TIME=${segment.scte.time}'
					}
					buffer += '\n'
				}
				.oatcls {
					match segment.scte.cue_type {
						.cue_start {
							buffer += '#EXT-OATCLS-SCTE35:${segment.scte.cue}\n#EXT-X-CUE-OUT:${segment.scte.time}\n'
						}
						.cue_mid {
							buffer += '#EXT-X-CUE-OUT-CONT:ElapsedTime=${segment.scte.elapsed},Duration=${segment.scte.time},SCTE35=${segment.scte.cue}\n'
						}
						.cue_end {
							buffer += '#EXT-X-CUE-IN\n'
						}
					}
				}
			}
		}

		if segment.key != Key{} && playlist.key != segment.key {
			buffer += '#EXT-X-KEY:METHOD=${segment.key.method.str()}'
			if segment.key.method != .@none {
				buffer += ',URI="${segment.key.uri}"'
				if segment.key.iv != '' {
					buffer += ',IV=${segment.key.iv}'
				}
				if segment.key.keyformat != '' {
					version =  set_newer_version(version, 5)
					buffer += ',KEYFORMAT="${segment.key.keyformat}"'
				}
				if segment.key.keyformatversions != '' {
					version =  set_newer_version(version, 5)
					buffer  += ',KEYFORMATVERSIONS="${segment.key.keyformatversions}"'
				}
			}
			buffer += '\n'
		}
		if segment.discontinuity {
			buffer += '#EXT-X-DISCONTINUITY\n'
		}

		if playlist.map == Map{} && segment.map != Map{} {
			version =  set_newer_version(version, 5)
			buffer += '#EXT-X-MAP:URI="${segment.map.uri}"'
			if segment.map.limit > 0 {
				buffer += ',BYTERANGE=${segment.map.limit}@${segment.map.offset}'
			}
			buffer += '\n'
		}
		if !(segment.program_date_time.second == 0 && segment.program_date_time.microsecond == 0) {
			f := segment.program_date_time.custom_format('YYYY-MM-DDTHH:mm:ss')
			buffer += '#EXT-X-PROGRAM-DATE-TIME:$f\n'
		}
		// segment.limit
		if segment.limit > 0 {
			buffer += '#EXT-X-BYTERANGE:${segment.limit}@${segment.offset}\n'
		}

		// custom tags
		if segment.custom_tags.len > 0 {
			for _, v in segment.custom_tags {
				custom_buf := v.encode()
				if custom_buf.len > 0 {
					buffer += '${custom_buf.str()}\n'
				}
			}
		}

		buffer += '#EXTINF:'
		str := cache[segment.duration]
		if str != '' {
			buffer += '$str'
		} else {
			buffer += '${segment.duration}'
		}

		buffer += ',${segment.title}\n${segment.uri}'
		if playlist.args != '' {
			buffer += '?${playlist.args}'
		}
		buffer += '\n'
	}
	if playlist.closed {
		buffer += '#EXT-X-ENDLIST\n'
	}

	return '#EXTM3U\n#EXT-X-VERSION:$version\n$buffer'
}

// `append` creates a segment and appends it to the end of `playlist`
pub fn (mut playlist MediaPlaylist) append(title string, uri string, duration f64) ? {
	mut segment := MediaSegment{}
	segment.title = title
	segment.uri = uri
	segment.duration = duration
	return playlist.append_segment(mut segment)
}

// `append_segment` appends `segment` to `playlist`
pub fn (mut playlist MediaPlaylist) append_segment(mut segment MediaSegment) ? {
	if playlist.head == playlist.tail && playlist.count > 0 {
		return error('Playlist is full')
	}

	segment.sequence_id = playlist.media_sequence
	if playlist.count > 0 {
		segment.sequence_id = playlist.segments[(playlist.capacity +
			playlist.tail - 1) % playlist.capacity].sequence_id + 1
	}
	playlist.segments[playlist.tail] = segment
	playlist.tail = (playlist.tail + 1) % playlist.capacity
	playlist.count += 1

	if playlist.target_duration < segment.duration {
		playlist.target_duration = math.ceil(segment.duration)
	}

	return
}

// `set_key` sets the EXT-X-KEY of `playlist`
pub fn (mut playlist MediaPlaylist) set_key(method KeyMethod, uri string, iv string, keyformat string, keyformatversions string) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}

	if keyformat != '' || keyformatversions != '' {
		playlist.version = set_newer_version(playlist.version, 5)
	}

	playlist.segments[playlist.last_segment()].key = Key{method, uri, iv, keyformat, keyformatversions}
	return
}

// `set_map` sets the EXT-X-MAP of `playlist`
pub fn (mut playlist MediaPlaylist) set_map(uri string, limit i64, offset i64) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}
	playlist.version = set_newer_version(playlist.version, 5)
	playlist.segments[playlist.last_segment()].map = &Map{uri, limit, offset}
	return
}

// set limit and offset for the current segment
pub fn (mut playlist MediaPlaylist) set_range(limit i64, offset i64) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}
	playlist.version = set_newer_version(playlist.version, 4)
	playlist.segments[playlist.last_segment()].limit = limit
	playlist.segments[playlist.last_segment()].offset = offset

	return
}

// `set_scte35` sets the SCTE cue format for the current segment
pub fn (mut playlist MediaPlaylist) set_scte35(scte35 &SCTE) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}
	playlist.segments[playlist.last_segment()].scte = scte35
	return
}

// `set_bitrate` sets the bitrate for the current segment
pub fn (mut playlist MediaPlaylist) set_bitrate(bitrate i64) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}
	playlist.segments[playlist.last_segment()].bitrate = bitrate
}

// `set_discontinuity` sets the discontinuity to true for the current segment
pub fn (mut playlist MediaPlaylist) set_discontinuity() ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}
	playlist.segments[playlist.last_segment()].discontinuity = true
	return
}

// `set_program_date_time` sets  the program_date_time value of the current segment
pub fn (mut playlist MediaPlaylist) set_program_date_time(value time.Time) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}
	playlist.segments[playlist.last_segment()].program_date_time = value
	return
}

// `set_custom_tag` sets custom media playlist tag
pub fn (mut playlist MediaPlaylist) set_custom_tag(tag CustomTag) {
	playlist.custom[tag.tag_name()] = tag
}

// `set_custom_segment_tag` sets a custom tag for the current segment
pub fn (playlist &MediaPlaylist) set_custom_segment_tag(tag CustomTag) ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}

	mut last := playlist.segments[playlist.last_segment()]
	last.custom_tags[tag.tag_name()] = tag

	return
}

// `remove` removes the last segment in `playlist`
pub fn (mut playlist MediaPlaylist) remove() ? {
	if playlist.count == 0 {
		return error('Playlist is empty')
	}

	playlist.head = (playlist.head + 1) % playlist.capacity
	playlist.count--

	if !playlist.closed {
		playlist.media_sequence++
	}

	return
}

// `close` closes the playlist (EXT-X-ENDLIST)
pub fn (mut playlist MediaPlaylist) close() {
	playlist.closed = true
}

// `count` returns the amount of segments in playlist
pub fn (playlist &MediaPlaylist) count() u32 {
	return playlist.count
}

// `version` returns the protocol version of `playlist`
pub fn (playlist &MediaPlaylist) version() u8 {
	return playlist.version
}

// `set_version` sets the protocol version of `playlist` to `new_version`
pub fn (mut playlist MediaPlaylist) set_version(new_version u8) {
	playlist.version = new_version
}

fn (playlist &MediaPlaylist) last_segment() u32 {
	if playlist.tail == 0 {
		return playlist.capacity - 1
	}
	return playlist.tail - 1
}

// `slide` removes a segment from the head of the segment slice and appends a new segment
pub fn (mut playlist MediaPlaylist) slide(title string, uri string, duration f64) {
	// ignore errors in slide
	if !playlist.closed {
		playlist.remove() or {}
	}

	playlist.append(title, uri, duration) or {}
}