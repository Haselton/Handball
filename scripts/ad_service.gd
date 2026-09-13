class_name AdService
extends Node

signal interstitial_closed
signal rewarded_continue_earned
signal billboard_loaded

var _rounds_since_ad := 0
var _last_ad_time_ms := -90000
var _interstitial_ready := false
var _rewarded_ready := false
var _native_billboard_ad

func initialize() -> void:
	preload_ads()
	_initialize_google_ads()

func _initialize_google_ads() -> void:
	if OS.get_name() != "Android":
		return
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status) -> void:
		_load_billboard_test_ad()
	MobileAds.initialize(listener)

func _load_billboard_test_ad() -> void:
	# Google's official Android native test unit. This can never record revenue
	# or contaminate the production account while the court is being tested.
	var options := NativeAdOptions.new()
	options.ad_choices_placement = AdChoicesPlacement.Values.TOP_RIGHT
	options.media_aspect_ratio = NativeMediaAspectRatio.Values.ANY
	NativeOverlayAd.load(
		"ca-app-pub-3940256099942544/2247696110",
		AdRequest.new(),
		options,
		func(ad, error) -> void:
			if error != null or ad == null:
				return
			_native_billboard_ad = ad
			var style := NativeTemplateStyle.new()
			style.template_id = NativeTemplateStyle.SMALL
			style.main_background_color = Color("eef0ec")
			var cta := NativeTemplateTextStyle.new()
			cta.background_color = Color("315d73")
			cta.text_color = Color.WHITE
			cta.font_size = 14
			cta.style = NativeTemplateFontStyle.Values.BOLD
			style.call_to_action_text = cta
			var screen_size := DisplayServer.screen_get_size()
			var initial_y := int(float(screen_size.y) * 0.17)
			_native_billboard_ad.render_template(style, AdPosition.custom(0, initial_y), AdSize.BANNER)
			_native_billboard_ad.on_template_rendered = func() -> void:
				var ad_width: float = float(_native_billboard_ad.get_template_width_in_pixels())
				var centered_x := maxi(0, int((float(screen_size.x) - ad_width) * 0.5))
				_native_billboard_ad.set_template_position(AdPosition.custom(centered_x, initial_y))
				billboard_loaded.emit()
	)

func _exit_tree() -> void:
	if _native_billboard_ad != null:
		_native_billboard_ad.destroy()
		_native_billboard_ad = null

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
