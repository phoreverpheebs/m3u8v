module m3u8

import time

const datetime = '2006-01-02T15:04:05.999999999Z07:00'

// playlist types
pub enum PlaylistType {
	@none
	master
	media
}

// media playlist sub-types
pub enum MediaType {
	@none
	event
	vod
}

pub fn (t MediaType) str() string {
	return match t {
		.event { 'EVENT' }
		.vod { 'VOD' }
		else { '' }
	}
}

// scte35 syntaxes
pub enum SCTE35_Syntax {
	scte_67_2014 // variable can't start with a number
	oatcls
}

// scte35 cue types
pub enum SCTE35_Cue_Type {
	cue_start
	cue_mid
	cue_end
}

// defined types of alternatives in master playlist
pub enum AlternativeType {
	@none
	audio
	video
	subtitles
	closed_captions
}

pub fn (t AlternativeType) str() string {
	return match t {
		.@none { 'NONE' }
		.audio { 'AUDIO' }
		.video { 'VIDEO' }
		.subtitles { 'SUBTITLES' }
		.closed_captions { 'CLOSED-CAPTIONS' }
	}
}

// defined key methods in EXT-X-KEY
pub enum KeyMethod {
	@none
	aes_128
	sample_aes
	sample_aes_ctr
}

pub fn (m KeyMethod) str() string {
	return match m {
		.@none { 'NONE' }
		.aes_128 { 'AES-128' }
		.sample_aes { 'SAMPLE-AES' }
		.sample_aes_ctr { 'SAMPLE-AES-CTR' }
	}
}

// playlist interface
pub interface Playlist {
	encode() string
}

struct DecodeState {
mut:
	list_type              PlaylistType
	m3u                    bool
	alternatives           []Alternative
	variant                Variant
	session_data           SessionData
	x_key                  Key
	x_map                  Map
	scte                   SCTE
	program_date_time      time.Time
	title                  string
	limit                  i64
	offset                 i64
	bitrate                i64
	duration               f64
	bitrate_done           bool
	stream_inf             bool
	inf                    bool
	range                  bool
	scte35                 bool
	discontinuity          bool
	program_date_time_done bool
	key                    bool
	map                    bool
	widevine               bool
	custom                 bool
	custom_map             map[string]CustomTag
}

pub struct Variant {
	VariantParams
pub mut:
	uri       string
	chunklist MediaPlaylist
}

pub struct VariantParams {
pub mut:
	program_id        u32
	bandwidth         u32
	average_bandwidth u32
	codecs            string
	resolution        Resolution
	audio             string
	video             string
	subtitles         string
	closed_captions   string
	name              string
	iframe            bool
	video_range       string
	hdcp_level        string
	frame_rate        f64
	stable_variant_id string
	alternatives      []Alternative
}

pub struct Widevine {
pub mut:
	audio_channels         u32
	audio_format           u32
	audio_profile_idc      u32
	audio_sample_size      u32
	audio_sample_frequency u32
	cypher_version         string
	ecm                    string
	video_format           u32
	video_frame_rate       u32
	video_level_idc        u32
	video_profile_idc      u32
	video_resolution       Resolution
	video_sar              string
}

pub struct MediaSegment {
pub mut:
	sequence_id u64
	title       string
	uri         string
	duration    f64
	limit       i64
	offset      i64
	bitrate     i64
	//
	key Key
	map Map
	//
	discontinuity bool
	//
	scte              SCTE
	program_date_time time.Time
	custom_tags       map[string]CustomTag
}

// EXT-X-KEY or EXT-X-SESSION-KEY
pub struct Key {
pub mut:
	method            KeyMethod // NONE, AES-128, SAMPLE-AES
	uri               string
	iv                string
	keyformat         string
	keyformatversions string
}

// EXT-X-MAP
pub struct Map {
pub mut:
	uri    string
	limit  i64
	offset i64
}

pub struct SCTE {
pub mut:
	syntax   SCTE35_Syntax
	cue_type SCTE35_Cue_Type
	cue      string
	id       string
	time     f64
	elapsed  f64
}

pub interface CustomTag {
	tag_name() string
	encode() []u8
	to_string() string
}

pub struct Alternative {
pub mut:
	group_id        string
	instream_id		string
	uri             string
	@type           AlternativeType
	language        string
	name            string
	default         bool
	autoselect     	bool
	channels		string
	forced          string
	characteristics string
	subtitles       string
}

pub struct Resolution {
pub mut:
	width  i64
	height i64
}

// returns {w}x{h}
pub fn (r Resolution) str() string {
	return '${r.width}x$r.height'
}

pub struct SessionData {
pub mut:
	data_id  string // required field - reverse dns naming convention
	value    string
	uri      string
	language string
}
