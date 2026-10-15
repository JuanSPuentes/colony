class_name Sprites
extends RefCounted
## Procedural pixel-art. Every sprite is drawn into a small Image with filled ellipses and
## lines, then shaded (lit from above) and outlined. Nothing here is a downloaded asset.

static var _cache := {}

const OUTLINE := Color("1d0f0a")


# --- Drawing helpers ----------------------------------------------------------------------

static func _new(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_px(img, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


static func _shade(img: Image, light: float, dark: float) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var above := src.get_pixel(x, y - 1).a if y > 0 else 0.0
			var below := src.get_pixel(x, y + 1).a if y < img.get_height() - 1 else 0.0
			if above < 0.5:
				img.set_pixel(x, y, c.lightened(light))
			elif below < 0.5:
				img.set_pixel(x, y, c.darkened(dark))


static func _outline(img: Image, col: Color) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a >= 0.5:
				continue
			var near := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < img.get_width() and ny < img.get_height() and src.get_pixel(nx, ny).a >= 0.5:
					near = true
					break
			if near:
				img.set_pixel(x, y, col)


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


# --- Ants -----------------------------------------------------------------------------------

static func ant_frames(caste: int) -> Array:
	var key := "ant%d" % caste
	if not _cache.has(key):
		var frames: Array[Texture2D] = []
		for f in 4:
			frames.append(_make_ant(caste, f))
		_cache[key] = frames
	return _cache[key]


static func _make_ant(caste: int, frame: int) -> ImageTexture:
	var body: Color
	var light: Color
	var dark: Color
	var w: int
	var h: int
	var abd: Array  # cx, cy, rx, ry
	var tho: Array
	var head: Array
	var leg_len: float
	match caste:
		Cfg.Caste.QUEEN:
			body = Color("7b3322")
			dark = Color("3a140c")
			w = 48
			h = 24
			abd = [14.0, 14.0, 12.0, 8.0]
			tho = [30.0, 13.0, 5.5, 4.4]
			head = [38.5, 13.0, 4.4, 3.8]
			leg_len = 9.0
		Cfg.Caste.SOLDIER:
			body = Color("a3321f")
			dark = Color("45120b")
			w = 32
			h = 18
			abd = [8.0, 10.0, 6.2, 4.6]
			tho = [17.0, 10.0, 3.8, 3.0]
			head = [24.5, 10.0, 5.2, 4.4]
			leg_len = 6.0
		Cfg.Caste.NURSE:
			body = Color("d8a23f")
			dark = Color("6b4a14")
			w = 26
			h = 14
			abd = [6.0, 8.0, 4.8, 3.4]
			tho = [14.0, 8.0, 3.0, 2.3]
			head = [19.5, 8.0, 3.2, 2.7]
			leg_len = 5.0
		_:
			body = Color("b8602f")
			dark = Color("5a2a14")
			w = 28
			h = 15
			abd = [7.0, 8.5, 5.6, 4.0]
			tho = [15.5, 8.5, 3.3, 2.5]
			head = [21.5, 8.5, 3.6, 2.9]
			leg_len = 5.5
	light = body.lightened(0.18)
	var img := _new(w + 2, h + 2)
	var o := 1.0
	var leg_col := dark.lightened(0.05)
	# Legs: three pairs under the thorax, swinging with the walk frame.
	var attach := [tho[0] - tho[2] * 0.6, tho[0], tho[0] + tho[2] * 0.6]
	var foot_y := int(tho[1] + leg_len) + 1
	for i in 3:
		var phase := float(frame) / 4.0 + float(i) / 3.0
		var swing := sin(phase * TAU) * 2.0
		var ax := int(attach[i] + o)
		var ay := int(tho[1] + tho[3] * 0.6 + o)
		_line(img, ax, ay, ax - 2 + int(swing), foot_y, leg_col)
		_line(img, ax, ay, ax + 3 - int(swing), foot_y, leg_col.darkened(0.2))
	# Body.
	_ellipse(img, abd[0] + o, abd[1] + o, abd[2], abd[3], body)
	_ellipse(img, tho[0] + o, tho[1] + o, tho[2], tho[3], body)
	_line(img, int(abd[0] + abd[2] * 0.5 + o), int(abd[1] + o), int(tho[0] - tho[2] + o), int(tho[1] + o), dark)
	_ellipse(img, head[0] + o, head[1] + o, head[2], head[3], body.darkened(0.08))
	if caste == Cfg.Caste.QUEEN:
		for k in 3:
			var sx := int(abd[0] - abd[2] * 0.5 + k * 5 + o)
			_line(img, sx, int(abd[1] - abd[3] + 2 + o), sx, int(abd[1] + abd[3] - 2 + o), Color("e0b247"))
	if caste == Cfg.Caste.SOLDIER:
		var hx := int(head[0] + head[2] + o)
		var hy := int(head[1] + o)
		_line(img, hx, hy - 2, hx + 3, hy - 1, Color("1b0a06"))
		_line(img, hx, hy + 2, hx + 3, hy + 1, Color("1b0a06"))
		_line(img, hx + 3, hy - 1, hx + 3, hy + 1, Color("e0d0b0"))
	_shade(img, 0.22, 0.18)
	# Antennae and eye after shading so they stay crisp.
	var ex := int(head[0] + head[2] * 0.4 + o)
	var ey := int(head[1] - head[3] * 0.3 + o)
	_px(img, ex, ey, Color("120806"))
	var ax0 := int(head[0] + head[2] * 0.6 + o)
	var ay0 := int(head[1] - head[3] * 0.8 + o)
	_line(img, ax0, ay0, ax0 + 3, ay0 - 4 - (frame % 2), dark)
	_line(img, ax0 + 3, ay0 - 4 - (frame % 2), ax0 + 6, ay0 - 3, dark)
	_outline(img, OUTLINE)
	return _tex(img)


# --- Spider -----------------------------------------------------------------------------------

static func spider_frames() -> Array:
	if not _cache.has("spider"):
		var frames: Array[Texture2D] = []
		for f in 4:
			frames.append(_make_spider(f))
		_cache["spider"] = frames
	return _cache["spider"]


static func _make_spider(frame: int) -> ImageTexture:
	var img := _new(66, 40)
	var body := Color("3f2c4d")
	var leg_c := Color("2a1c34")
	var o := 1.0
	for side in 2:
		for i in 4:
			var ax := 33 + i * 3 - 2
			var phase := float(frame) / 4.0 + float(i) * 0.25 + float(side) * 0.5
			var sw := sin(phase * TAU) * 2.5
			var dir := -1 if i < 2 else 1
			if i % 2 == 1:
				dir = 1
			var kx := ax + dir * (7 + i)
			var ky := 8 - i % 2 * 2 + side
			var fx := ax + dir * (16 + i * 2) + int(sw)
			var col := leg_c if side == 0 else leg_c.lightened(0.25)
			_line(img, ax, 20, kx, ky, col)
			_line(img, kx, ky, fx, 37, col)
			_line(img, ax, 21, kx, ky + 1, col)
			_line(img, kx, ky + 1, fx, 37, col)
	_ellipse(img, 19 + o, 22 + o, 13.0, 10.0, body)
	_ellipse(img, 38 + o, 20 + o, 8.0, 6.5, body.lightened(0.12))
	# Pale hourglass mark on the abdomen.
	for k in 4:
		_px(img, 17 + k, 18 + int(k / 2.0), Color("d4c2e0"))
		_px(img, 17 + k, 26 - int(k / 2.0), Color("d4c2e0"))
	_shade(img, 0.2, 0.2)
	# Eyes and fangs.
	for p in [Vector2i(43, 17), Vector2i(45, 18), Vector2i(43, 20), Vector2i(46, 21)]:
		_px(img, p.x, p.y, Color("ff3b30"))
	_line(img, 46, 24, 48, 28, Color("e8dcc8"))
	_line(img, 44, 25, 45, 29, Color("e8dcc8"))
	_outline(img, OUTLINE)
	return _tex(img)


# --- Brood and items -----------------------------------------------------------------------------

static func brood_tex(stage: int) -> Texture2D:
	var key := "brood%d" % stage
	if _cache.has(key):
		return _cache[key]
	var img: Image
	match stage:
		Cfg.Stage.EGG:
			img = _new(10, 12)
			_ellipse(img, 5, 6.5, 3.4, 4.4, Color("f5eed8"))
			_shade(img, 0.1, 0.12)
			_px(img, 4, 4, Color.WHITE)
			_outline(img, Color("8a7b5a"))
		Cfg.Stage.LARVA:
			img = _new(18, 11)
			for k in 5:
				_ellipse(img, 4.0 + k * 2.6, 6.0 - sin(k * 0.8) * 1.5, 2.6, 2.8, Color("f0e2b4"))
			_ellipse(img, 3.0, 5.0, 2.4, 2.4, Color("d1a64e"))
			_shade(img, 0.1, 0.1)
			_outline(img, Color("8a7040"))
		_:
			img = _new(14, 17)
			_ellipse(img, 7, 8.5, 4.6, 6.4, Color("d8b67c"))
			for y in [5, 8, 11]:
				_line(img, 4, y, 10, y, Color("b08f55"))
			_shade(img, 0.1, 0.12)
			_outline(img, Color("7b5f33"))
	var tex := _tex(img)
	_cache[key] = tex
	return tex


static func leaf_piece() -> Texture2D:
	if _cache.has("leaf"):
		return _cache["leaf"]
	var img := _new(14, 10)
	_ellipse(img, 7, 5, 5.6, 3.4, Color("62c24c"))
	_line(img, 2, 5, 12, 4, Color("a6e089"))
	_shade(img, 0.15, 0.2)
	_outline(img, Color("1f5a24"))
	var t := _tex(img)
	_cache["leaf"] = t
	return t


static func droplet() -> Texture2D:
	if _cache.has("drop"):
		return _cache["drop"]
	var img := _new(8, 10)
	_ellipse(img, 4, 6, 2.8, 3.2, Color("5fb8f0"))
	_px(img, 4, 2, Color("5fb8f0"))
	_px(img, 4, 3, Color("5fb8f0"))
	_px(img, 3, 5, Color("d8f0ff"))
	_outline(img, Color("1c4f78"))
	var t := _tex(img)
	_cache["drop"] = t
	return t


## Leafy plant that ants harvest. `level` 0..3: more leaves when the stock is higher.
static func bush(level: int) -> Texture2D:
	var key := "bush%d" % level
	if _cache.has(key):
		return _cache[key]
	var img := _new(60, 44)
	var stem := Color("6b4a2a")
	var bases := [Vector2i(30, 42)]
	var tips := [Vector2i(10, 20), Vector2i(22, 10), Vector2i(38, 8), Vector2i(50, 18), Vector2i(30, 14), Vector2i(16, 30), Vector2i(46, 30), Vector2i(30, 26), Vector2i(8, 36)]
	var count: int = [0, 3, 6, 9][level]
	for i in count:
		var t: Vector2i = tips[i]
		_line(img, bases[0].x, bases[0].y, t.x, t.y + 6, stem)
	_line(img, 30, 43, 30, 36, stem)
	_line(img, 29, 43, 29, 36, stem)
	for i in count:
		var t2: Vector2i = tips[i]
		var g := Color("4fae44").lerp(Color("86d65b"), float(i % 3) / 3.0)
		_ellipse(img, t2.x, t2.y, 7.5, 5.0, g)
		_ellipse(img, t2.x + 1, t2.y - 1, 4.0, 2.2, g.lightened(0.18))
	_shade(img, 0.12, 0.2)
	_outline(img, Color("1f4a22"))
	var tx := _tex(img)
	_cache[key] = tx
	return tx


# --- Terrain tiles ---------------------------------------------------------------------------------

static func _hash(x: int, y: int, v: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (v * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) % 1000


const SOIL_BASE := ["7d5838", "6a4930", "553b25", "42301f"]


static func soil_tile(band: int, variant: int) -> Image:
	var key := "soil%d_%d" % [band, variant]
	if _cache.has(key):
		return _cache[key]
	var base := Color(SOIL_BASE[band])
	var img := _new(Cfg.CELL, Cfg.CELL)
	for y in Cfg.CELL:
		for x in Cfg.CELL:
			var n := _hash(x, y, variant + band * 7)
			var c := base
			if n < 110:
				c = base.darkened(0.14)
			elif n > 930:
				c = base.lightened(0.12)
			elif n > 880:
				c = base.lightened(0.05)
			img.set_pixel(x, y, c)
	# Pebbles.
	var pebbles := 1 + variant % 2
	for k in pebbles:
		var px := _hash(k, variant, 3) % 12 + 1
		var py := _hash(k, variant, 4) % 12 + 1
		var pc := Color("958776").darkened(0.08 * band)
		for dy in 2:
			for dx in 2 + k % 2:
				img.set_pixel(px + dx, py + dy, pc)
		img.set_pixel(px, py, pc.lightened(0.2))
	# Roots on some variants.
	if variant % 3 == 0 and band < 3:
		var rc := Color("a07a4a").darkened(0.1 * band)
		var ry := _hash(variant, band, 9) % 8 + 4
		for x in Cfg.CELL:
			var yy := ry + int(sin(x * 0.7 + variant) * 1.6)
			img.set_pixel(x, clampi(yy, 0, Cfg.CELL - 1), rc)
	_cache[key] = img
	return img


static func rock_tile(variant: int) -> Image:
	var key := "rock%d" % variant
	if _cache.has(key):
		return _cache[key]
	var img := _new(Cfg.CELL, Cfg.CELL)
	var base := Color("57566a")
	for y in Cfg.CELL:
		for x in Cfg.CELL:
			var n := _hash(x, y, variant + 40)
			var c := base
			if n < 160:
				c = base.darkened(0.18)
			elif n > 860:
				c = base.lightened(0.16)
			if y < 3 and n > 300:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)
	for x in Cfg.CELL:
		img.set_pixel(x, Cfg.CELL - 1, base.darkened(0.35))
	_cache[key] = img
	return img


static func bedrock_tile() -> Image:
	if _cache.has("bedrock"):
		return _cache["bedrock"]
	var img := _new(Cfg.CELL, Cfg.CELL)
	for y in Cfg.CELL:
		for x in Cfg.CELL:
			var n := _hash(x, y, 77)
			img.set_pixel(x, y, Color("302e38") if n > 200 else Color("26242e"))
	_cache["bedrock"] = img
	return img


const ROOM_BASE := ["2b1d15", "46303a", "5a4127", "3d4328", "263a46"]
const ROOM_SPECK := ["3a281d", "caa24c", "e8d9a8", "86993f", "5b8aa6"]


## Tunnel tile; `mask` bits: 1 soil above, 2 soil right, 4 soil below, 8 soil left.
static func tunnel_tile(room: int, mask: int, variant: int) -> Image:
	var key := "tun%d_%d_%d" % [room, mask, variant]
	if _cache.has(key):
		return _cache[key]
	var base := Color(ROOM_BASE[room])
	var speck := Color(ROOM_SPECK[room])
	var img := _new(Cfg.CELL, Cfg.CELL)
	for y in Cfg.CELL:
		for x in Cfg.CELL:
			var n := _hash(x, y, variant + room * 11)
			var c := base
			if n > 950:
				c = speck
			elif n < 80:
				c = base.darkened(0.2)
			if mask & 1 and y < 4:
				c = c.darkened(0.12 * (4 - y))
			img.set_pixel(x, y, c)
	var edge := Color("120a07")
	var lip := Color("5a3d27")
	for i in Cfg.CELL:
		if mask & 1:
			img.set_pixel(i, 0, edge)
			img.set_pixel(i, 1, lip.darkened(0.5))
		if mask & 4:
			img.set_pixel(i, Cfg.CELL - 1, edge)
			img.set_pixel(i, Cfg.CELL - 2, base.lightened(0.25))
			img.set_pixel(i, Cfg.CELL - 3, base.lightened(0.12))
		if mask & 8:
			img.set_pixel(0, i, edge)
			img.set_pixel(1, i, lip.darkened(0.5))
		if mask & 2:
			img.set_pixel(Cfg.CELL - 1, i, edge)
			img.set_pixel(Cfg.CELL - 2, i, lip.darkened(0.5))
	if room == Cfg.Room.DRAIN:
		for x in range(2, Cfg.CELL - 2, 4):
			img.set_pixel(x, 6 + (x / 4) % 2, Color("7fb4d0"))
	_cache[key] = img
	return img
