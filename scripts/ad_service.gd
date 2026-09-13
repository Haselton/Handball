class_name AdService
extends Node

signal interstitial_closed
signal rewarded_continue_earned

var _rounds_since_ad := 0
var _last_ad_time_ms := -90000
var _interstitial_ready := false
var _rewarded_ready := false

func initialize() -> void:
	# The production AdMob plugin is connected here. Test builds deliberately
	# continue without ads when no Android plugin singleton is installed.
	preload_ads()
	show_billboard_banner()

func show_billboard_banner() -> void:
	# HandballAdMob owns the Android anchored-adaptive view. Its implementation
	# maps this placement to the reserved billboard face and must use Google's
	# test unit ID in debug builds. The Godot scene keeps a TEST AD house sign
	# visible when the native bridge is unavailable.
	if Engine.has_singleton("HandballAdMob"):
		var bridge = Engine.get_singleton("HandballAdMob")
		if bridge.has_method("show_billboard_banner"):
			bridge.show_billboard_banner()

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
