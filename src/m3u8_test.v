module m3u8

fn test_master_decode_reencode() ? {
	playlist := decode(master_playlist_data, false) or { panic(err) }
	surely_master := decode_master_playlist(master_playlist_data, false) or { panic(err) }

	if playlist is MasterPlaylist {
		assert playlist.version() == 3
		assert playlist.variants.len == 5
		assert playlist.variants[0].bandwidth == 300000
		assert playlist.variants[1].uri == 'chunklist-b600000.m3u8'
		assert playlist.variants[2].program_id == 1
		assert playlist.variants[3] == Variant{
			program_id: 1
			bandwidth: 1000000
			uri: 'chunklist-b1000000.m3u8'
		}
		assert playlist.variants[4].codecs == 'mp4a.40.5'
		// reencode
		encoded := playlist.encode()
		assert encoded == master_playlist_data
		assert playlist == surely_master
	}
}

const master_playlist_data = '#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=300000
chunklist-b300000.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=600000
chunklist-b600000.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=850000
chunklist-b850000.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1000000
chunklist-b1000000.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1500000,CODECS="mp4a.40.5"
chunklist-b1500000.m3u8
'

fn test_master_decode_with_codecs_and_alts() ? {
	playlist := decode(master_playlist_with_codecs_and_alts_data, false) or {
		panic(err)
	}

	if playlist is MasterPlaylist {
		assert playlist.version() == 4
		assert playlist.variants[0].video == 'low'
		assert playlist.variants[0].codecs == 'avc1.42c015,mp4a.40.2'
		assert playlist.variants[0].alternatives.len == 3
		assert playlist.variants[0].alternatives[0].group_id == 'low'
		assert playlist.variants[1].alternatives[1].uri == 'mid/centerfield/audio-video.m3u8'
		assert playlist.variants[1].alternatives[2].name == 'Dugout'
		assert playlist.variants[2].alternatives[0] == Alternative{
			@type: .video
			group_id: 'hi'
			name: 'Main'
			default: true
			uri: 'hi/main/audio-video.m3u8'
		}
		assert playlist.variants[2].alternatives[1].@type == .video
		assert playlist.variants[2].alternatives[1].@type.str() == 'VIDEO'
		assert playlist.variants[2].uri == 'hi/main/audio-video.m3u8'
		assert playlist.variants[3].uri == 'main/audio-only.m3u8'
	}
}

const master_playlist_with_codecs_and_alts_data = '#EXTM3U
#EXT-X-VERSION:4
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="low",NAME="Main",DEFAULT=YES,URI="low/main/audio-video.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="low",NAME="Centerfield",DEFAULT=NO,URI="low/centerfield/audio-video.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="low",NAME="Dugout",DEFAULT=NO,URI="low/dugout/audio-video.m3u8"
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1280000,VIDEO="low",CODECS="avc1.42c015,mp4a.40.2"
low/main/audio-video.m3u8
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="mid",NAME="Main",DEFAULT=YES,URI="mid/main/audio-video.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="mid",NAME="Centerfield",DEFAULT=NO,URI="mid/centerfield/audio-video.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="mid",NAME="Dugout",DEFAULT=NO,URI="mid/dugout/audio-video.m3u8"
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2560000,VIDEO="mid",CODECS="avc1.42c015,mp4a.40.2"
mid/main/audio-video.m3u8
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="hi",NAME="Main",DEFAULT=YES,URI="hi/main/audio-video.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="hi",NAME="Centerfield",DEFAULT=NO,URI="hi/centerfield/audio-video.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="hi",NAME="Dugout",DEFAULT=NO,URI="hi/dugout/audio-video.m3u8"
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=7680000,VIDEO="hi",CODECS="avc1.42c015,mp4a.40.2"
hi/main/audio-video.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=65000,CODECS="mp4a.40.5",CODECS="avc1.42c015,mp4a.40.2"
main/audio-only.m3u8
'

fn test_media_decode() ? {
	playlist := decode(media_playlist_data, false) or { panic(err) }
	surely_media := decode_media_playlist(media_playlist_data, 1024, false) or { panic(err) }

	assert surely_media.version() == 7
	assert surely_media.target_duration == f64(5)
	assert surely_media.media_type == .vod
	assert surely_media.map.uri == 'test_map.mp4'
	assert surely_media.independent_segments == true
	assert surely_media.segments[0].bitrate == 7766

	if playlist is MediaPlaylist {
		assert playlist.version() == 7
		assert playlist.target_duration == f64(5)
		assert playlist.media_type == .vod
		assert playlist.map.uri == 'test_map.mp4'
		assert playlist.independent_segments == true
		assert playlist.segments[0].duration == 4.08742
		assert playlist.segments[0].bitrate == 7766
		assert playlist.segments[1].uri == 'video_sdr_-2.mp4'
		assert playlist.count() == 7
		assert playlist.closed == true
		assert playlist.segments[playlist.count() - 1].bitrate == 9629
	}
}

const media_playlist_data = '#EXTM3U
#EXT-X-TARGETDURATION:5
#EXT-X-VERSION:7
#EXT-X-MEDIA-SEQUENCE:1
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="test_map.mp4"
#EXTINF:4.08742,	
#EXT-X-BITRATE:7766
video_sdr_-1.mp4
#EXTINF:4.96329,	
#EXT-X-BITRATE:9190
video_sdr_-2.mp4
#EXTINF:4.42108,	
#EXT-X-BITRATE:6478
video_sdr_-3.mp4
#EXTINF:3.92058,	
#EXT-X-BITRATE:7378
video_sdr_-4.mp4
#EXTINF:4.50450,	
#EXT-X-BITRATE:8030
video_sdr_-5.mp4
#EXTINF:3.25325,	
#EXT-X-BITRATE:8495
video_sdr_-6.mp4
#EXTINF:4.87988,	
#EXT-X-BITRATE:9629
video_sdr_-7.mp4
#EXT-X-ENDLIST
'

fn test_complex_master_decode() ? {
	playlist := decode(complex_media_playlist_data, false) or { panic(err) }

	if playlist is MasterPlaylist {
		assert playlist.version() == 7
		assert playlist.independent_segments == true
		assert playlist.variants.len == 17
		assert playlist.session_data[0].data_id == 'com.title'
		assert playlist.session_data[1] == SessionData{
			data_id: 'com.poster'
			value: 'https://cdn.test/video_image_poster.jpg'
			language: 'en-us'
		}
		assert playlist.variants[0].alternatives[0].uri == 'https://apple_hls_test.test/video_09_sdr_-.m3u8'
		assert playlist.variants[0].alternatives[1].group_id == 'audio-HE-stereo-64'
		assert playlist.variants[1].uri == 'https://apple_hls_test.test/video_14_sdr_-.m3u8'
		assert playlist.variants[2].bandwidth == 689255
		assert playlist.variants[2].video_range == 'SDR'
		assert playlist.variants[3].codecs == 'avc1.640028'
		assert playlist.variants[3].average_bandwidth == 896340
		assert playlist.variants[3].resolution == Resolution{
			width: 1916
			height: 908
		}
		assert playlist.variants[4].stable_variant_id == 'a7d469'
		assert playlist.variants[5].audio == 'audio-HE-stereo-32'
		assert playlist.variants[6].frame_rate == 23.976
		assert playlist.variants[7].codecs == 'avc1.64001f,mp4a.40.5'
		assert playlist.variants[8].closed_captions == 'NONE'
		assert playlist.variants[playlist.variants.len - 2].average_bandwidth == 5513479
		assert playlist.variants[playlist.variants.len - 1].resolution.str() == '1916x908'
		assert playlist.session_key[0].method == .sample_aes
		assert playlist.session_key[0].keyformat == 'example_format'
		assert playlist.session_key[1].uri == 'example_key2'
		assert playlist.session_key[1].keyformatversions == '1'
	}
}

// edit playlist to be less apple like
const complex_media_playlist_data = '
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-SESSION-DATA:DATA-ID="com.title",VALUE="Test Title",LANGUAGE="en-us"
#EXT-X-SESSION-DATA:DATA-ID="com.poster",VALUE="https://cdn.test/video_image_poster.jpg",LANGUAGE="en-us"


#-- en (4) --
#EXT-X-MEDIA:TYPE=AUDIO,LANGUAGE="en",GROUP-ID="audio-HE-stereo-32",NAME="English",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="https://apple_hls_test.test/video_09_sdr_-.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,LANGUAGE="en",GROUP-ID="audio-HE-stereo-64",NAME="English",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="https://apple_hls_test.test/video_10_sdr_-.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,LANGUAGE="en",GROUP-ID="audio-stereo-128",NAME="English",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="https://apple_hls_test.test/video_11_sdr_-.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,LANGUAGE="en",GROUP-ID="audio-stereo-256",NAME="English",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="https://apple_hls_test.test/video_12_sdr_-.m3u8"

#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=181858,BANDWIDTH=187466,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=730x346,URI="https://apple_hls_test.test/video_13_sdr_-.m3u8"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=359054,BANDWIDTH=370858,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=862x408,URI="https://apple_hls_test.test/video_14_sdr_-.m3u8"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=666050,BANDWIDTH=689255,VIDEO-RANGE=SDR,CODECS="avc1.640020",RESOLUTION=1392x660,URI="https://apple_hls_test.test/video_15_sdr_-.m3u8"
#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=896340,BANDWIDTH=920726,VIDEO-RANGE=SDR,CODECS="avc1.640028",RESOLUTION=1916x908,URI="https://apple_hls_test.test/video_16_sdr_-.m3u8"

#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1854980,BANDWIDTH=2162618,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.2",AUDIO="audio-stereo-128",FRAME-RATE=23.976,RESOLUTION=1114x528,STABLE-VARIANT-ID="a7d469"
https://apple_hls_test.test/video_17_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=242652,BANDWIDTH=296306,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.5",AUDIO="audio-HE-stereo-32",FRAME-RATE=23.976,RESOLUTION=520x246,STABLE-VARIANT-ID="5b6b03"
https://apple_hls_test.test/video_18_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=312261,BANDWIDTH=392520,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.5",AUDIO="audio-HE-stereo-32",FRAME-RATE=23.976,RESOLUTION=592x280,STABLE-VARIANT-ID="f84bb1"
https://apple_hls_test.test/video_19_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=439578,BANDWIDTH=548780,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.5",AUDIO="audio-HE-stereo-32",FRAME-RATE=23.976,RESOLUTION=658x312,STABLE-VARIANT-ID="8d0423"
https://apple_hls_test.test/video_20_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=678477,BANDWIDTH=828544,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.5",AUDIO="audio-HE-stereo-64",FRAME-RATE=23.976,RESOLUTION=730x346,STABLE-VARIANT-ID="51c33e"
https://apple_hls_test.test/video_21_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=964889,BANDWIDTH=1159964,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.5",AUDIO="audio-HE-stereo-64",FRAME-RATE=23.976,RESOLUTION=836x396,STABLE-VARIANT-ID="9ee2ca"
https://apple_hls_test.test/video_22_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1298921,BANDWIDTH=1532654,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f,mp4a.40.5",AUDIO="audio-HE-stereo-64",FRAME-RATE=23.976,RESOLUTION=862x408,STABLE-VARIANT-ID="af40c2"
https://apple_hls_test.test/video_23_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2444473,BANDWIDTH=2901219,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.640020,mp4a.40.2",AUDIO="audio-stereo-128",FRAME-RATE=23.976,RESOLUTION=1392x660,STABLE-VARIANT-ID="30bf90"
https://apple_hls_test.test/video_24_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3257205,BANDWIDTH=3840279,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.640020,mp4a.40.2",AUDIO="audio-stereo-128",FRAME-RATE=23.976,RESOLUTION=1394x660,STABLE-VARIANT-ID="73bd6d"
https://apple_hls_test.test/video_25_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3471665,BANDWIDTH=4150909,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio-stereo-256",FRAME-RATE=23.976,RESOLUTION=1916x908,STABLE-VARIANT-ID="2ddf32"
https://apple_hls_test.test/video_26_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4455569,BANDWIDTH=5321114,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio-stereo-256",FRAME-RATE=23.976,RESOLUTION=1916x908,STABLE-VARIANT-ID="0c3253"
https://apple_hls_test.test/video_27_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=5513479,BANDWIDTH=6749053,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.640029,mp4a.40.2",AUDIO="audio-stereo-256",FRAME-RATE=23.976,RESOLUTION=1916x908,STABLE-VARIANT-ID="efa552"
https://apple_hls_test.test/video_28_sdr_-.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=8437438,BANDWIDTH=9901148,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.640029,mp4a.40.2",AUDIO="audio-stereo-256",FRAME-RATE=23.976,RESOLUTION=1916x908,STABLE-VARIANT-ID="083cc4"
https://apple_hls_test.test/video_29_sdr_-.m3u8

#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="example_key1",KEYFORMAT="example_format",KEYFORMATVERSIONS="1"
#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="example_key2",KEYFORMAT="example_format",KEYFORMATVERSIONS="1"
'

fn test_master_encode() ? {
	playlist := MasterPlaylist{
		session_data: [SessionData{
			data_id: 'com.test.vlang'
			value: 'vlang'
			uri:'https://thing.vlang'
			language:'en-us'
		}]
		variants: [Variant{
			uri: 'example_variant.m3u8'
			program_id: 1
			bandwidth: 5435
			average_bandwidth: 485
			codecs: 'mp4a.40.2'
			resolution: Resolution{1920, 1080}
			audio: 'audio-stereo-256'
			iframe: false
			video_range: 'SDR'
			hdcp_level: 'TYPE-0'
			frame_rate: 23.976
			stable_variant_id: 'ffffff'
			alternatives: [Alternative{
				group_id: 'audio-stereo-256'
				uri: 'https://apple_hls_test.test/video_09_sdr_-.m3u8'
				@type: .audio
				language: 'en'
				name: 'ENGLISH'
				default: true
				autoselect: true
				channels: "2"
			}]
		}]
	}

	assert playlist.encode() == '#EXTM3U
#EXT-X-VERSION:7
#EXT-X-SESSION-DATA:DATA-ID="com.test.vlang",VALUE="vlang",URI="https://thing.vlang",LANGUAGE="en-us"

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-stereo-256",NAME="ENGLISH",DEFAULT=YES,AUTOSELECT=YES,CHANNELS=2,LANGUAGE="en",URI="https://apple_hls_test.test/video_09_sdr_-.m3u8"
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=5435,AVERAGE-BANDWIDTH=485,CODECS="mp4a.40.2",RESOLUTION=1920x1080,VIDEO-RANGE=SDR,HDCP-LEVEL=TYPE-0,AUDIO="audio-stereo-256",FRAME-RATE=23.976
example_variant.m3u8
'
}

fn test_media_encode() ? {
	mut playlist := new_media_playlist(4)
	
	for i := 0; i < 4; i++ {
		playlist.append('', 't0${i}.ts', 10)?
	}

	assert playlist.count() == 4
	assert playlist.media_sequence == 0

	for idx, seqid := u32(0), u64(0); idx < 3; idx++, seqid++ {
		segidx := (playlist.head + idx) % playlist.capacity
		seguri := 't${seqid:02}.ts'
		seg := playlist.segments[segidx]
		assert seg.uri == seguri
		assert seg.sequence_id == seqid
	}

	playlist.slide('', 't04.ts', 10)
	assert playlist.count() == 4
	assert playlist.media_sequence == 1

	for idx, seqid := u32(0), u64(1); idx < 3; idx++, seqid++ {
		segidx := (playlist.head + idx) % playlist.capacity
		seguri := 't${seqid:02}.ts'
		seg := playlist.segments[segidx]
		assert seg.uri == seguri
		assert seg.sequence_id == seqid
	}

	playlist.slide('', 't05.ts', 10)
	playlist.slide('', 't06.ts', 10)
	assert playlist.count() == 4
	assert playlist.media_sequence == 3

	for idx, seqid := u32(0), u64(3); idx < 3; idx++, seqid++ {
		segidx := (playlist.head + idx) % playlist.capacity
		seguri := 't${seqid:02}.ts'
		seg := playlist.segments[segidx]
		assert seg.uri == seguri
		assert seg.sequence_id == seqid
	}
	
	assert playlist.encode() == '#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:3
#EXT-X-TARGETDURATION:10
#EXTINF:10,
t03.ts
#EXTINF:10,
t04.ts
#EXTINF:10,
t05.ts
#EXTINF:10,
t06.ts
'
}