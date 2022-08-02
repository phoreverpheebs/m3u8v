<h1>v-m3u8</h1>

V library for decoding and encoding/generating m3u8 playlist files widely used in the HTTP Live Streaming protocol.

<h2>Features</h2>

* Supports playlists up to protocol version 7
* Allows for parsing media and master playlists
* Auto-detection for input streams
* Support for DRM systems and non standard Widevine tags

<h2>Installation</h2>

via vpm:

`v install phoreverpheebs.m3u8`

via git:

`git clone https://github.com/phoreverpheebs/v-m3u8.git ~/.vmodules/phoreverpheebs/m3u8`

<h2>Examples</h2>

```v
import phoreverpheebs.m3u8

fn main() {
	playlist := m3u8.decode_from_file('playlist.m3u8', true) or { panic(err) }

	if playlist is m3u8.MasterPlaylist {
		println(playlist.version())
		println(playlist.variants)
		eprintln('master')
	} else if playlist is m3u8.MediaPlaylist {
		println(playlist.version())
		println(playlist.segments)
		eprintln('media')
	}
}
```

<h2>Plans</h2>

- [ ] Add examples
- [ ] Documentation
- [ ] Custom Tags
- [ ] Custom Decoder
- [ ] Protocol version 8

<h2>References</h2>

This repository was inspired by grafov's implementation of the protocol in Go https://github.com/grafov/m3u8

<h2>Other languages</h2>

* https://github.com/grafov/m3u8 in Golang
* https://github.com/globocom/m3u8 in Python
* https://github.com/zencoder/m3uzi in Ruby
* https://github.com/Jeanvf/M3U8Paser in Objective C
* https://github.com/tedconf/node-m3u8 in Javascript
* http://sourceforge.net/projects/m3u8parser/ in Java
* https://github.com/karlll/erlm3u8 in Erlang
