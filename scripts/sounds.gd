extends Node
# ============================================================
#  every sound in the game is generated when the game starts.
#  no audio files, no downloading, nothing to import.
#  each one is a tiny beep that slides from one pitch to another.
# ============================================================

var players = {}
var streams = {}
var muted = false


func _ready():
	# name: [start pitch, end pitch, how long, shape, volume]
	# i could only hear the parry at first, and the reason was this table.
	# "shoot" was 0.05 seconds long at volume 0.10, which comes out at about
	# a tenth of the loudness of the others, so it was basically silence.
	# the fade also eats most of a very short sound before it gets loud.
	# everything is a bit longer and louder now, and the quiet ones that
	# happen all the time (shoot) are the ones i pulled down on purpose
	streams["parry"] = make_beep(880, 1500, 0.12, "square", 0.34)
	streams["perfect"] = make_beep(1200, 2200, 0.18, "square", 0.38)
	streams["kill"] = make_beep(180, 60, 0.26, "noise", 0.55)
	streams["hurt"] = make_beep(220, 70, 0.36, "saw", 0.46)
	streams["shoot"] = make_beep(320, 240, 0.11, "sine", 0.30)
	streams["wave"] = make_beep(520, 1040, 0.28, "sine", 0.32)
	streams["clear"] = make_beep(660, 1180, 0.24, "sine", 0.30)
	streams["over"] = make_beep(300, 80, 0.55, "saw", 0.40)
	streams["type"] = make_beep(1400, 1400, 0.06, "square", 0.20)
	streams["cover"] = make_beep(300, 120, 0.09, "noise", 0.30)
	streams["taunt"] = make_beep(500, 900, 0.20, "square", 0.30)

	# four copies of each so fast sounds do not cut each other off
	for key in streams:
		var pool = []
		var i = 0
		while i < 4:
			var p = AudioStreamPlayer.new()
			p.stream = streams[key]
			p.volume_db = -4.0
			add_child(p)
			pool.append(p)
			i = i + 1
		players[key] = pool


func play(name):
	if muted:
		return
	if not players.has(name):
		return
	for p in players[name]:
		if not p.playing:
			p.play()
			return
	players[name][0].play()


# ------------------------------------------------------------
#  build one beep by hand, sample by sample
# ------------------------------------------------------------
func make_beep(start_hz, end_hz, length, shape, volume):
	var rate = 22050
	var samples = int(length * rate)
	var data = PackedByteArray()
	data.resize(samples * 2)

	var phase = 0.0
	var i = 0
	while i < samples:
		var t = float(i) / float(rate)
		var k = t / length          # 0 at the start, 1 at the end

		# slide the pitch from start to end
		var hz = start_hz * pow(end_hz / start_hz, k)
		phase = phase + hz / float(rate)

		var value = 0.0
		if shape == "square":
			if fmod(phase, 1.0) < 0.5:
				value = 1.0
			else:
				value = -1.0
		elif shape == "saw":
			value = 2.0 * fmod(phase, 1.0) - 1.0
		elif shape == "sine":
			value = sin(phase * TAU)
		else:
			value = randf_range(-1.0, 1.0)

		# fade out so it does not click at the end
		var fade = pow(1.0 - k, 2.0)
		var sample = int(clamp(value * fade * volume, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, sample)
		i = i + 1

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
