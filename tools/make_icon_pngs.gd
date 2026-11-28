extends SceneTree
func svg(path: String, px: int) -> Image:
	var im := Image.new()
	im.load_svg_from_buffer(FileAccess.get_file_as_bytes(path), px / 512.0)
	im.convert(Image.FORMAT_RGBA8)
	return im
func _init():
	var d := "D:/Games/block_boom_godot/design/icons/"
	var o := "D:/Games/block_boom_godot/art/"
	var bg := Color("2b2a67")
	svg(d + "v4.svg", 192).save_png(o + "icon_192.png")
	# Адаптивный значок Android: рисунок в центральных 2/3, остальное срезает маска
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	var art := svg(d + "v4_fg.svg", 330)
	fg.blit_rect(art, Rect2i(0, 0, 330, 330), Vector2i(51, 51))
	fg.save_png(o + "icon_fg_432.png")
	var b := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	b.fill(bg)
	b.fill_rect(Rect2i(0, 51 + int(196 * 330.0 / 512.0), 432, int(120 * 330.0 / 512.0)), Color("463f9e"))
	b.save_png(o + "icon_bg_432.png")
	# Экран открытия: рисунок по центру прозрачного холста, фон задаётся цветом в настройках
	var sp := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	sp.blit_rect(svg(d + "v4_fg.svg", 1024), Rect2i(0, 0, 1024, 1024), Vector2i.ZERO)
	sp.save_png(o + "splash.png")
	quit()
