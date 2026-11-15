extends MeshInstance3D
# ============================================================
#  a soft round glow that always turns to face you.
#  there is no real bloom in low quality mode, so every glowing
#  thing gets one of these stuck to it. it is just a flat disc
#  with a see-through picture on it.
#
#  i build the picture by hand, pixel by pixel, with maths instead
#  of art: bright in the middle, fading out in a curve to nothing
#  at the edge. same trick as the beeps in sounds.gd.
# ============================================================

var colour = Color("#4df0ff")
var size = 90.0
var strength = 0.55


func _ready():
	build_disc()
	# it must not write depth, or the disc hides the thing it glows for
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build_disc():
	var texture = make_glow_texture()

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# turn to face the camera and ignore the light in the room
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	mat.albedo_texture = texture
	mat.albedo_color = Color(colour.r, colour.g, colour.b, strength)

	# one flat square. the picture in the middle is round, the corners
	# are transparent, so it looks like a disc
	var quad = QuadMesh.new()
	quad.size = Vector2(size, size)
	mesh = quad
	material_override = mat


func make_glow_texture():
	var tex = ImageTexture.new()
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)

	var y = 0
	while y < 64:
		var x = 0
		while x < 64:
			# how far this pixel is from the middle, 0 in the centre
			# and 1 at the edge of the circle
			var dx = (x - 31.5) / 31.5
			var dy = (y - 31.5) / 31.5
			var d = sqrt(dx * dx + dy * dy)
			var a = 0.0
			if d < 1.0:
				# bright in the middle, and it fades away quickly
				# towards the rim. the two powers are just what looked
				# good when i messed about with the numbers
				a = pow(1.0 - d, 2.2)
				a = a * (0.45 + 0.55 * pow(1.0 - d, 6.0))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
			x = x + 1
		y = y + 1

	tex.set_image(img)
	return tex


# used when a parried bullet changes colour
func set_colour(new_colour):
	colour = new_colour
	if material_override != null:
		material_override.albedo_color = Color(new_colour.r, new_colour.g, new_colour.b, strength)
