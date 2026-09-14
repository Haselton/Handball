class_name AdService
extends Node

signal interstitial_closed
signal rewarded_continue_earned

var _billboard_banner

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
	_billboard_banner = AdView.new(
		"ca-app-pub-3940256099942544/6300978111",
		billboard_size,
		AdPosition.custom(banner_x, banner_y)
	)
	_billboard_banner.load_ad(AdRequest.new())
func _exit_tree() -> void:
	if _billboard_banner != null:
		_billboard_banner.destroy()
		_billboard_banner = null

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
