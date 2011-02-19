-- How to decode an audio file with Lua, using LuaJIT FFI and ffmpeg...
-- Michal Kottman, 2011

local FILENAME = arg[1] or 'song.mp3'
local SECTION = print

SECTION "Initializing the FFI library"

local ffi = require 'ffi'
local C = ffi.C

--[[
To recreate ffmpeg.h, create a file tmp.h with the following content
(or more, or less, depending on what you want):

#include "config.h"
#include "libavutil/avstring.h"
#include "libavutil/pixdesc.h"
#include "libavformat/avformat.h"
#include "libavdevinputContexte/avdevinputContexte.h"
#include "libswscale/swscale.h"
#include "libavcodec/audioconvert.h"
#include "libavcodec/colorspace.h"
#include "libavcodec/opt.h"
#include "libavcodec/avfft.h"
#include "libavfilter/avfilter.h"
#include "libavfilter/avfiltergraph.h"
#include "libavfilter/graphparser.h"

Then run gcc -E -I $PATH_TO_FFMPEG_SRC tmp.h > ffmpeg.h
]]

local avcodec = ffi.load('avcodec-52')
local avformat = ffi.load('avformat-52')
local avutil = ffi.load('avutil-50')
local header = assert(io.open('ffmpeg.h')):read('*a')
ffi.cdef(header)

function avAssert(err)
	if err < 0 then
		local errbuf = ffi.new("uint8_t[256]")
		local ret = avutil.av_strerror(err, errbuf, 256)
		if ret ~= -1 then
			error(ffi.string(errbuf), 2)
		else
			error('Unknown AV error: '..tostring(ret), 2)
		end
	end
	return err
end

SECTION "Initializing the avcodec and avformat libraries"

avcodec.avcodec_init()
avcodec.avcodec_register_all()
avformat.av_register_all()

SECTION "Opening file"

local pinputContext = ffi.new("AVFormatContext*[1]")
avAssert(avformat.av_open_input_file(pinputContext, FILENAME, nil, 0, nil))
local inputContext = pinputContext[0]

avAssert(avformat.av_find_stream_info(inputContext))

SECTION "Finding audio stream"

local audioCtx
local nStreams = tonumber(inputContext.nb_streams)
for i=1,nStreams do
	local stream = inputContext.streams[i-1]
	local ctx = stream.codec
	if ctx.codec_type == C.AVMEDIA_TYPE_AUDIO then
		local codec = avcodec.avcodec_find_decoder(ctx.codec_id)
		avAssert(avcodec.avcodec_open(ctx, codec))
		audioCtx = ctx
	end
end
if not audioCtx then error('Unable to find audio stream') end

print("Bitrate:", tonumber(audioCtx.bit_rate))
print("Channels:", tonumber(audioCtx.channels))
print("Sample rate:", tonumber(audioCtx.sample_rate))
print("Sample type:", ({[0]="u8", "s16", "s32", "flt", "dbl"})[audioCtx.sample_fmt])

SECTION "Decoding"

local AVCODEC_MAX_AUDIO_FRAME_SIZE = 192000

local packet = ffi.new("AVPacket")
local temp_frame = ffi.new("int16_t[?]", AVCODEC_MAX_AUDIO_FRAME_SIZE)
local frame_size = ffi.new("int[1]")

local all_samples = {}
local total_samples = 0

while tonumber(avformat.url_feof(inputContext.pb)) == 0 do
	local ret = avAssert(avformat.av_read_frame(inputContext, packet))

	frame_size[0] = AVCODEC_MAX_AUDIO_FRAME_SIZE
	local n = avcodec.avcodec_decode_audio3(audioCtx, temp_frame, frame_size, packet)
	if n == -1 then break
	elseif n < 0 then avAssert(n) end

	local size = tonumber(frame_size[0])/2 -- frame_size is in bytes
	local frame = ffi.new("int16_t[?]", size)
	ffi.copy(frame, temp_frame, size*2)
	all_samples[#all_samples + 1] = frame
	total_samples = total_samples + size
end

SECTION "Merging samples"

local samples = ffi.new("int16_t[?]", total_samples)
local offset = 0
for _,s in ipairs(all_samples) do
	local size = ffi.sizeof(s)
	ffi.copy(samples + offset, s, size)
	offset = offset + size/2
end

SECTION "Processing"

-- The `samples` array is now ready for some processing! :)

-- ... like writing it raw to a file

local out = assert(io.open('samples.raw', 'wb'))
local size = ffi.sizeof(samples)
out:write(ffi.string(samples, size))
out:close()

-- Now you can open it in any audio processing program to see that it works.
-- In Audacity: Project -> Import Raw Data (and fill out according to info)
