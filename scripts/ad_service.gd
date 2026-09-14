class_name AdService
extends Node

signal interstitial_closed
signal rewarded_continue_earned

var _billboard_banner
var _billboard_frame: Panel

var _rounds_since_ad := 0
var _last_ad_time_ms := -90000
var _interstitial_ready := false
var _rewarded_ready := false

func initialize() -> void:
	preload_ads()
	_initialize_banner_ads()

func _initialize_banner_ads() -> void:
	if OS.get_name() != "Android":
		return
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status) -> void:
		_show_billboard_banner()
	MobileAds.initialize(listener)

func _show_billboard_banner() -> void:
	# Standard banner only. Google's official test unit is used in debug APKs.
	var screen_size := DisplayServer.screen_get_size()
	var density := maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0)
	var logical_width := float(screen_size.x) / density
	var logical_height := float(screen_size.y) / density
	# AdMob only serves standard inventory reliably. Keep the creative at the
	# supported 320x50 banner size and size the 3D billboard around it.
	var billboard_size := AdSize.new(320, 50)
	var banner_x := maxi(0, int((logical_width - 320.0) * 0.5))
	var banner_y := maxi(0, int(logical_height * 0.223))
	_build_billboard_frame(banner_x, banner_y, logical_width, logical_height)
	_billboard_banner = AdView.new(
		"ca-app-pub-3940256099942544/6300978111",
		billboard_size,
		AdPosition.custom(banner_x, banner_y)
	)
	_billboard_banner.load_ad(AdRequest.new())

func _build_billboard_frame(banner_x: int, banner_y: int, logical_width: float, logical_height: float) -> void:
	# The Android AdView is drawn above Godot, so the reliable way to frame it
	# is a slightly larger Godot panel directly behind the exact native rect.
	# Coordinates are converted from Android dp to the stretched Godot viewport.
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_x := viewport_size.x / logical_width
	var scale_y := viewport_size.y / logical_height
	var inset_dp := 6.0

	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)

	_billboard_frame = Panel.new()
	_billboard_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_billboard_frame.position = Vector2(
		(float(banner_x) - inset_dp) * scale_x,
		(float(banner_y) - inset_dp) * scale_y
	)
	_billboard_frame.size = Vector2(
		(320.0 + inset_dp * 2.0) * scale_x,
		(50.0 + inset_dp * 2.0) * scale_y
	)
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color("071018")
	bezel.border_color = Color("149cff")
	bezel.set_border_width_all(maxi(3, int(4.0 * minf(scale_x, scale_y))))
	bezel.set_corner_radius_all(maxi(3, int(5.0 * minf(scale_x, scale_y))))
	_billboard_frame.add_theme_stylebox_override("panel", bezel)
	layer.add_child(_billboard_frame)

func _exit_tree() -> void:
	if _billboard_banner != null:
		_billboard_banner.destroy()
		_billboard_banner = null
	if _billboard_frame != null:
		_billboard_frame.queue_free()
		_billboard_frame = null

func preload_ads() -> void:
	_interstitial_ready = false
	_rewarded_ready = false
	if Engine.has_singleton("HandballAdMob"):
		var bridge = Engine.get_singleton("HandballAdMob")
		bridge.load_interstitial()
		bridge.load_rewarded()

func note_round_finished() -> void:
	_rounds_since_ad += 1

func should_show_interstitial() -> bool:
	var elapsed := Time.get_ticks_msec() - _last_ad_time_ms
	return _rounds_since_ad >= 2 and elapsed >= 60000

func show_interstitial_or_continue() -> void:
	if Engine.has_singleton("HandballAdMob") and should_show_interstitial():
		var bridge = Engine.get_singleton("HandballAdMob")
		if bridge.is_interstitial_ready():
			_rounds_since_ad = 0
			_last_ad_time_ms = Time.get_ticks_msec()
			bridge.show_interstitial()
			return
	interstitial_closed.emit()

func show_rewarded_continue() -> void:
	if Engine.has_singleton("HandballAdMob"):
		var bridge = Engine.get_singleton("HandballAdMob")
		if bridge.is_rewarded_ready():
			bridge.show_rewarded()
			return
	# Rewarded continuation remains disabled when an ad cannot actually play.
