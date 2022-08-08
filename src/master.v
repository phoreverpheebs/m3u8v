module m3u8

import strconv

// `MasterPlaylist` is the master playlist type
pub struct MasterPlaylist {
pub mut:
	session_data []SessionData
	session_key  []Key
	variants     []Variant
	uri_params   string
	custom_tags  map[string]CustomTag
mut:
	version              u8 = 3
	independent_segments bool
}

// `new_master_playlist` creates a new master playlist
pub fn new_master_playlist() MasterPlaylist {
	return MasterPlaylist{}
}

// `decode_master_playlist` decodes data into a master playlist
// useful for when you know a playlist is of type master
// `strict` will return syntax errors if true
pub fn decode_master_playlist(data string, strict bool) ?MasterPlaylist {
	mut state := DecodeState{}
	mut playlist := new_master_playlist()

	for _, line in data.split_into_lines() {
		if line.len < 1 || line == '\r' {
			continue
		}

		decode_line_of_master(mut playlist, mut state, line, strict) or {
			if strict {
				return err
			}
		}
	}

	if strict && !state.m3u {
		return error('m3u8: Unable to find #EXTM3U tag')
	}

	return playlist
}

[direct_array_access]
fn decode_line_of_master(mut playlist MasterPlaylist, mut state DecodeState, raw_line string, strict bool) ? {
	mut line := raw_line.trim_space()

	match true {
		// start
		line == '#EXTM3U' {
			state.m3u = true
		}
		// version
		line.starts_with('#EXT-X-VERSION:') {
			state.list_type = .master
			playlist.version = u8(strconv.parse_uint(line.all_after('#EXT-X-VERSION:'),
				10, 8) or {
				if strict {
					return error('m3u8: Unable to parse playlist version: $err')
				}
				3
			})
		}
		// independent segments
		line == '#EXT-X-INDEPENDENT-SEGMENTS' {
			playlist.set_independent_segments(true)
		}
		// EXT-X-MEDIA
		line.starts_with('#EXT-X-MEDIA:') {
			mut alt := Alternative{}
			state.list_type = .master
			for k, v in decode_params(line.all_after('#EXT-X-MEDIA:')) {
				match k {
					'TYPE' {
						alt.@type = match v {
							'AUDIO' { .audio }
							'VIDEO' { .video }
							'SUBTITLES' { .subtitles }
							'CLOSED-CAPTIONS' { .closed_captions }
							else { .@none }
						}
					}
					'GROUP-ID' {
						alt.group_id = v
					}
					'INSTREAM-ID' {
						alt.instream_id = v
					}
					'LANGUAGE' {
						alt.language = v
					}
					'NAME' {
						alt.name = v
					}
					'DEFAULT' {
						if v.to_upper() == 'YES' {
							alt.default = true
						} else if v.to_upper() == 'NO' {
							alt.default = false
						} else if strict {
							return error('m3u8: value of attribute "DEFAULT" must be "YES" or "NO"')
						}
					}
					'AUTOSELECT' {
						if v.to_upper() == 'YES' {
							alt.autoselect = true
						} else if v.to_upper() == 'NO' {
							alt.autoselect = false
						} else if strict {
							return error('m3u8: :value of attribute "AUTOSELECT" must be "YES" or "NO"')
						}
					}
					'CHANNELS' {
						alt.channels = v
					}
					'FORCED' {
						alt.forced = v
					}
					'CHARACTERISTICS' {
						alt.characteristics = v
					}
					'SUBTITLES' {
						alt.subtitles = v
					}
					'URI' {
						alt.uri = v
					}
					else {}
				}
			}
			state.alternatives << alt
		}
		// EXT-X-STREAM-INF
		line.starts_with('#EXT-X-STREAM-INF:') && !state.stream_inf {
			state.stream_inf = true
			state.list_type = .master
			state.variant = Variant{}
			if state.alternatives.len > 0 {
				state.variant.alternatives = state.alternatives
				state.alternatives = []
			}
			for k, v in decode_params(line.all_after('#EXT-X-STREAM-INF:')) {
				match k {
					'PROGRAM-ID' {
						value := strconv.parse_uint(v, 10, 32) or {
							if strict {
								return error('m3u8: Unable to parse program ID: $err')
							}
							0
						}
						state.variant.program_id = u32(value)
					}
					'BANDWIDTH' {
						value := strconv.parse_uint(v, 10, 32) or {
							if strict {
								return error('m3u8: Unable to parse bandwidth: $err')
							}
							0
						}
						state.variant.bandwidth = u32(value)
					}
					'AVERAGE-BANDWIDTH' {
						value := strconv.parse_uint(v, 10, 32) or {
							if strict {
								return error('m3u8: Unable to parse average bandwidth: $err')
							}
							0
						}
						state.variant.average_bandwidth = u32(value)
					}
					'CODECS' {
						state.variant.codecs = v
					}
					'RESOLUTION' {
						res := v.split('x')
						if res.len < 2 {
							if strict {
								return error('m3u8: Unable to parse resolution')
							}
						} else {
							width := strconv.parse_int(res[0], 10, 64) or {
								if strict {
									return error('m3u8: Unable to parse resolution width: $err')
								}
								0
							}
							height := strconv.parse_int(res[1], 10, 64) or {
								if strict {
									return error('m3u8: Unable to parse resolution height: $err')
								}
								0
							}
							state.variant.resolution = Resolution{
								width: width
								height: height
							}
						}
					}
					'AUDIO' {
						state.variant.audio = v
					}
					'VIDEO' {
						state.variant.video = v
					}
					'SUBTITLES' {
						state.variant.subtitles = v
					}
					'CLOSED-CAPTIONS' {
						state.variant.closed_captions = v
					}
					'NAME' {
						state.variant.name = v
					}
					'VIDEO-RANGE' {
						state.variant.video_range = v
					}
					'HDCP-LEVEL' {
						state.variant.hdcp_level = v
					}
					'FRAME-RATE' {
						value := strconv.atof64(v) or {
							if strict {
								return error('m3u8: Unable to parse frame rate: $err')
							}
							0
						}
						state.variant.frame_rate = value
					}
					'STABLE-VARIANT-ID' {
						state.variant.stable_variant_id = v
					}
					else {}
				}
			}
			playlist.variants << state.variant
		}
		// STREAM-INF URI
		!line.starts_with('#') && state.stream_inf {
			state.stream_inf = false
			playlist.variants[playlist.variants.len - 1].uri = line
		}
		// EXT-X-I-FRAME-STREAM-INF
		line.starts_with('#EXT-X-I-FRAME-STREAM-INF:') {
			state.list_type = .master
			state.variant = Variant{}
			playlist.version = set_newer_version(playlist.version, 4)
			state.variant.iframe = true
			if state.alternatives.len > 0 {
				state.variant.alternatives = state.alternatives
				state.alternatives = []
			}
			for k, v in decode_params(line.all_after('#EXT-X-I-FRAME-STREAM-INF:')) {
				match k {
					'URI' {
						state.variant.uri = v
					}
					'PROGRAM-ID' {
						value := strconv.atoi(v) or {
							if strict {
								return error('m3u8: Unable to parse program ID: $err')
							}
							0
						}
						state.variant.program_id = u32(value)
					}
					'BANDWIDTH' {
						value := strconv.atoi(v) or {
							if strict {
								return error('m3u8: Unable to parse bandwidth: $err')
							}
							0
						}
						state.variant.bandwidth = u32(value)
					}
					'AVERAGE-BANDWIDTH' {
						value := strconv.atoi(v) or {
							if strict {
								return error('m3u8: Unable to parse average bandwidth: $err')
							}
							0
						}
						state.variant.average_bandwidth = u32(value)
					}
					'CODECS' {
						state.variant.codecs = v
					}
					'RESOLUTION' {
						res := v.split('x')
						if res.len < 2 {
							if strict {
								return error('m3u8: Unable to parse resolution')
							}
						} else {
							width := strconv.parse_int(res[0], 10, 64) or {
								if strict {
									return error('m3u8: Unable to parse resolution width: $err')
								}
								0
							}
							height := strconv.parse_int(res[1], 10, 64) or {
								if strict {
									return error('m3u8: Unable to parse resolution height: $err')
								}
								0
							}
							state.variant.resolution = Resolution{
								width: width
								height: height
							}
						}
					}
					'AUDIO' {
						state.variant.audio = v
					}
					'VIDEO' {
						state.variant.video = v
					}
					'VIDEO-RANGE' {
						state.variant.video_range = v
					}
					'HDCP-LEVEL' {
						state.variant.hdcp_level = v
					}
					else {}
				}
			}
			playlist.variants << state.variant
		}
		line.starts_with('#EXT-X-SESSION-DATA:') {
			state.list_type = .master
			state.session_data = SessionData{}
			for k, v in decode_params(line.all_after('#EXT-X-SESSION-DATA:')) {
				match k {
					'DATA-ID' { state.session_data.data_id = v }
					'VALUE' { state.session_data.value = v }
					'LANGUAGE' { state.session_data.language = v }
					else {}
				}
			}
			playlist.session_data << state.session_data
		}
		line.starts_with('#EXT-X-SESSION-KEY:') {
			state.list_type = .master
			state.x_key = Key{}
			for k, v in decode_params(line.all_after('#EXT-X-SESSION-KEY:')) {
				match k {
					'METHOD' { state.x_key.method = match v {
						'AES-128' { .aes_128 }
						'SAMPLE-AES' { .sample_aes }
						'SAMPLE-AES-CTR' { .sample_aes_ctr }
						else { .@none }
					} }
					'URI' { state.x_key.uri = v }
					'IV' { state.x_key.iv = v }
					'KEYFORMAT' { state.x_key.keyformat = v }
					'KEYFORMATVERSIONS' { state.x_key.keyformatversions = v }
					else {}
				}
			}
			playlist.session_key << state.x_key
		}
		else {}
	}

	return
}

// `encode` returns playlist encoded as an m3u8 playlist file
[direct_array_access]
pub fn (playlist MasterPlaylist) encode() string {
	mut version := playlist.version
	mut buffer := ''

	if playlist.independent_segments {
		buffer += '#EXT-X-INDEPENDENT-SEGMENTS\n'
	}

	if playlist.custom_tags.len > 0 {
		// encode custom tags
	}

	if playlist.session_data.len > 0 {
		version = set_newer_version(version, 7)
		for _, session in playlist.session_data {
			buffer += '#EXT-X-SESSION-DATA:DATA-ID="$session.data_id"'

			if session.value != '' {
				buffer += ',VALUE="$session.value"'
			}
			if session.value != '' {
				buffer += ',URI="$session.uri"'
			}
			if session.language != '' {
				buffer += ',LANGUAGE="$session.language"'
			}
			buffer += '\n'
		}
		buffer += '\n' // gotta make the m3u8 look pretty
	}

	// ensure alts are written once
	mut written := map[string]bool{}

	for _, variant in playlist.variants {
		if variant.alternatives.len > 0 {
			for _, alternative in variant.alternatives {
				alt_key := '${alternative.@type.str()}-$alternative.group_id-$alternative.name-$alternative.language'
				if written[alt_key] {
					continue
				}
				written[alt_key] = true

				mut alt_attr := ''

				buffer += '#EXT-X-MEDIA:'

				alt_attr += 'TYPE=${alternative.@type.str()}'
				if alternative.group_id != '' {
					alt_attr += ',GROUP-ID="$alternative.group_id"'
				}
				if alternative.name != '' {
					alt_attr += ',NAME="$alternative.name"'
				}
				alt_attr += ',DEFAULT='
				if alternative.default {
					alt_attr += 'YES'
				} else {
					alt_attr += 'NO'
				}
				alt_attr += ',AUTOSELECT='
				if alternative.autoselect {
					alt_attr += 'YES'
				} else {
					alt_attr += 'NO'
				}
				if alternative.channels != '' {
					alt_attr += ',CHANNELS=$alternative.channels'
				}
				if alternative.language != '' {
					alt_attr += ',LANGUAGE="$alternative.language"'
				}
				if alternative.forced != '' {
					alt_attr += ',FORCED="$alternative.forced"'
				}
				if alternative.characteristics != '' {
					alt_attr += ',CHARACTERISTICS="$alternative.characteristics"'
				}
				if alternative.subtitles != '' {
					alt_attr += ',SUBTITLES="$alternative.subtitles"'
				}
				if alternative.uri != '' {
					alt_attr += ',URI="$alternative.uri"'
				}
				buffer += '$alt_attr\n'
			}
		}
		mut iframe_string := 'PROGRAM-ID=$variant.program_id,BANDWIDTH=$variant.bandwidth'
		if variant.average_bandwidth != 0 {
			iframe_string += ',AVERAGE-BANDWIDTH=$variant.average_bandwidth'
		}
		if variant.codecs != '' {
			iframe_string += ',CODECS="$variant.codecs"'
		}
		if variant.resolution.width != 0 && variant.resolution.height != 0 {
			iframe_string += ',RESOLUTION=$variant.resolution.str()'
		}
		if variant.video != '' {
			iframe_string += ',VIDEO="$variant.video"'
		}
		if variant.video_range != '' {
			iframe_string += ',VIDEO-RANGE=$variant.video_range'
		}
		if variant.hdcp_level != '' {
			iframe_string += ',HDCP-LEVEL=$variant.hdcp_level'
		}
		if variant.iframe {
			buffer += '#EXT-X-I-FRAME-STREAM-INF:$iframe_string'
			if variant.uri != '' {
				buffer += ',URI="$variant.uri"'
			}
			version = set_newer_version(version, 4)
		} else {
			buffer += '#EXT-X-STREAM-INF:$iframe_string'
			if variant.audio != '' {
				buffer += ',AUDIO="$variant.audio"'
			}
			if variant.closed_captions != '' {
				buffer += ',CLOSED-CAPTIONS='
				if variant.closed_captions == 'NONE' {
					buffer += variant.closed_captions
				} else {
					buffer += '"$variant.closed_captions"'
				}
			}
			if variant.subtitles != '' {
				buffer += ',SUBTITLES="$variant.subtitles"'
			}
			if variant.name != '' {
				buffer += ',NAME="$variant.name"'
			}
			if variant.frame_rate != 0 {
				buffer += ',FRAME-RATE=$variant.frame_rate'
			}
			buffer += '\n$variant.uri'
			if playlist.uri_params != '' {
				if variant.uri.contains('?') {
					buffer += '&'
				} else {
					buffer += '?'
				}
				buffer += playlist.uri_params
			}
		}
		buffer += '\n'
	}

	if playlist.session_key.len > 0 {
		version = set_newer_version(version, 7)
		for _, key in playlist.session_key {
			if key.method != .@none {
				buffer += '#EXT-X-SESSION-KEY:METHOD=${key.method.str()}'
				if key.method == .sample_aes {
					version = set_newer_version(version, 5)
				}
				if key.uri != '' {
					buffer += ',URI="$key.uri"'
				}
				if key.iv != '' {
					buffer += ',IV="$key.iv"'
				}
				if key.keyformat != '' {
					buffer += ',KEYFORMAT="$key.keyformat"'
					version = set_newer_version(version, 5)
				}
				if key.keyformatversions != '' {
					buffer += ',KEYFORMATVERSIONS="$key.keyformatversions"'
					version = set_newer_version(version, 5)
				}
				buffer += '\n'
			}
		}
		buffer += '\n'
	}

	return '#EXTM3U\n#EXT-X-VERSION:$version\n$buffer'
}

// `set_independent_segments` sets `EXT-X-INDEPENDENT-SEGMENTS`
pub fn (mut playlist MasterPlaylist) set_independent_segments(b bool) {
	playlist.independent_segments = b
}

// `version` returns the protocol version of `playlist`
pub fn (playlist &MasterPlaylist) version() u8 {
	return playlist.version
}
