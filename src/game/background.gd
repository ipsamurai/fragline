class_name Background
extends CanvasLayer
## Sky gradient + two parallax silhouette layers, generated per map style.
## Each layer is baked once into a single StaticDraw mesh (one draw call per layer);
## each frame only the layer offsets move.

const LAYERS := [0.15, 0.4]     # scroll factors (far, mid)

var _theme: Dictionary
var _style := ""
var _map_size := Vector2.ZERO
var _sky: Node2D
var _layers: Array[Node2D] = []
var _sky_g: StaticDraw                 # baked meshes (must outlive _draw(): commands hold their RIDs)
var _layer_g: Array[StaticDraw] = [null, null]


func setup(level: Level) -> void:
	layer = -10
	_theme = level.theme
	_style = level.def.style
	_map_size = level.size_px
	_sky = Node2D.new()
	StaticDraw.setup_item(_sky)
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	for i in LAYERS.size():
		var n := Node2D.new()
		StaticDraw.setup_item(n)
		n.draw.connect(_draw_layer.bind(n, i))
		add_child(n)
		_layers.append(n)
	get_viewport().size_changed.connect(_sky.queue_redraw)


func follow(cam_center: Vector2) -> void:
	var half := get_viewport().get_visible_rect().size * 0.5
	for i in _layers.size():
		_layers[i].position = half - cam_center * LAYERS[i]


## Rebuilt on every redraw (only happens when the viewport is resized).
func _draw_sky() -> void:
	var s := get_viewport().get_visible_rect().size
	var top: Color = _theme.sky_top
	var bottom: Color = _theme.sky_bottom
	var g := StaticDraw.new()
	_sky_g = g
	g.grad(Rect2(Vector2.ZERO, s), top, bottom)
	if _style in ["city", "space", "ice", "jungle"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 90:
			var p := Vector2(rng.randf() * s.x, rng.randf() * s.y * 0.7)
			g.circle(p, rng.randf_range(0.6, 1.8), Color(1, 1, 1, rng.randf_range(0.15, 0.6)))
	if _style == "space":
		var c := Vector2(s.x * 0.78, s.y * 0.3)
		g.circle(c, 120.0, Color(_theme.edge, 0.08))
		g.circle(c, 95.0, _theme.mid.lightened(0.15))
		g.circle(c + Vector2(-22, -18), 70.0, _theme.mid.lightened(0.25))
	g.draw_on(_sky)


func _draw_layer(n: Node2D, i: int) -> void:
	if _layer_g[i] == null:
		_layer_g[i] = _bake_layer(i)
	_layer_g[i].draw_on(n)


func _bake_layer(i: int) -> StaticDraw:
	var g := StaticDraw.new()
	var s: float = LAYERS[i]
	var view := get_viewport().get_visible_rect().size
	var col: Color = _theme.far if i == 0 else _theme.mid
	var x0 := -view.x
	var x1 := _map_size.x * s + view.x * 2.0
	var base := _map_size.y * s + view.y * 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_style) + i
	var light: Color = Color(_theme.edge, 0.35 if i == 1 else 0.2)
	var x := x0
	while x < x1:
		var wdt := rng.randf_range(60, 180) * (1.0 + i * 0.4)
		var hgt := rng.randf_range(140, 420) * (0.8 + i * 0.35)
		match _style:
			"jungle":
				g.circle(Vector2(x, base), hgt * 0.7, col)
				g.polygon(PackedVector2Array([Vector2(x + wdt * 0.5, base - hgt * 1.1),
						Vector2(x + wdt, base - hgt * 0.4), Vector2(x, base - hgt * 0.4)]), col.darkened(0.15))
			"ice":
				g.polygon(PackedVector2Array([Vector2(x - wdt, base), Vector2(x, base - hgt),
						Vector2(x + wdt * 0.4, base - hgt * 0.7), Vector2(x + wdt * 1.2, base)]), col)
				g.polygon(PackedVector2Array([Vector2(x, base - hgt), Vector2(x + 18, base - hgt + 40),
						Vector2(x - 20, base - hgt + 44)]), Color(1, 1, 1, 0.25))
			"space":
				if rng.randf() < 0.35:
					g.rect(Rect2(x, base - hgt * 0.6, wdt * 0.6, 8), col)
					g.rect(Rect2(x + wdt * 0.25, base - hgt * 0.6, 6, hgt), col)
			_:
				# Buildings / industrial blocks / foundry stacks with lit windows.
				var r := Rect2(x, base - hgt, wdt, hgt + view.y)
				g.rect(r, col)
				if _style == "foundry" and rng.randf() < 0.5:
					g.rect(Rect2(x + wdt * 0.3, base - hgt - 120, 22, 120), col)
					g.circle(Vector2(x + wdt * 0.3 + 11, base - hgt - 128), 14, Color(_theme.edge, 0.15))
				var wy := base - hgt + 16
				while wy < base - 10:
					var wx := x + 10
					while wx < x + wdt - 14:
						if rng.randf() < 0.18:
							g.rect(Rect2(wx, wy, 6, 4), light)
						wx += 14
					wy += 18
		x += wdt + rng.randf_range(-20, 40)
	# Ground fill so nothing shows below the silhouettes.
	g.rect(Rect2(x0, base, x1 - x0, view.y * 2.0), col)
	return g
