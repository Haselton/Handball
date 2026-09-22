class_name AdService
extends Node

signal interstitial_closed
signal rewarded_continue_earned
signal status_message(message: String)
signal privacy_options_changed(required: bool)

var diagnostic_status := "Ads have not initialized"
var _billboard_banner
var _interstitial
var _rewarded
var _interstitial_loading := false
var _rewarded_loading := false
var _initialized := false
var _initializing := false
var _showing := false
var _reward_earned := false
var _rounds_since_ad := 0
var _last_ad_time_ms := -90000
var _banner_retry_delay := 30.0
var _banner_retry: Timer
var _consent_retry: Timer
var _consent_form

func initialize() -> void:
	if OS.get_name() != "Android":
		diagnostic_status = "Ads require Android"
		return
	for plugin in ["PoingGodotAdMob", "PoingGodotAdMobAdView", "PoingGodotAdMobConsentInformation", "PoingGodotAdMobUserMessagingPlatform"]:
		if not Engine.has_singleton(plugin):
			diagnostic_status = "Missing Android ad component: " + plugin
			push_error(diagnostic_status)
			return
	_banner_retry = Timer.new()
	_banner_retry.one_shot = true
	_banner_retry.timeout.connect(_load_banner)
	add_child(_banner_retry)
	_consent_retry = Timer.new()
	_consent_retry.one_shot = true
	_consent_retry.wait_time = 60.0
	_consent_retry.timeout.connect(_update_consent)
	add_child(_consent_retry)
	_update_consent()

func _update_consent() -> void:
	diagnostic_status = "Checking ad privacy settings"
	UserMessagingPlatform.consent_information.update(ConsentRequestParameters.new(), _consent_updated, _consent_failed)

func _consent_updated() -> void:
	var info = UserMessagingPlatform.consent_information
	privacy_options_changed.emit(info.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED)
	if info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(_consent_loaded, _consent_failed)
	else:
		_start_ads_if_allowed()

func _consent_loaded(form: ConsentForm) -> void:
	_consent_form = form
	form.show(func(error):
		_consent_form = null
		if error != null:
			_consent_failed(error)
		else:
			_start_ads_if_allowed()
	)

func _consent_failed(error: FormError) -> void:
	diagnostic_status = "Privacy check: %s" % error.message
	push_warning(diagnostic_status)
	_start_ads_if_allowed()
	if not _initialized:
		_consent_retry.start()

func _start_ads_if_allowed() -> void:
	var consent := UserMessagingPlatform.consent_information.get_consent_status()
	if consent != ConsentInformation.ConsentStatus.OBTAINED and consent != ConsentInformation.ConsentStatus.NOT_REQUIRED:
		return
	if _initialized or _initializing:
		return
	_initializing = true
	diagnostic_status = "Initializing AdMob"
	# Connect before initialize: a cached initialization can complete immediately.
	var bridge = Engine.get_singleton("PoingGodotAdMob")
	bridge.connect("on_initialization_complete", _on_ads_initialized, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	bridge.initialize()

func _on_ads_initialized(_status: Dictionary) -> void:
	_initialized = true
	_initializing = false
	_load_banner()
	preload_ads()

func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(error):
		if error != null:
			status_message.emit("PRIVACY OPTIONS UNAVAILABLE. TRY AGAIN.")
		# Drop cached ads before making requests under the updated choice.
		_destroy_ads()
		_initialized = false
		_start_ads_if_allowed()
	)

func _unit(kind: String) -> String:
	return str(ProjectSettings.get_setting("handball/ads/" + kind + "_id", ""))

func _load_banner() -> void:
	if not _initialized or _unit("banner").is_empty():
		return
	if _billboard_banner != null:
		_billboard_banner.destroy()
	# Retain the approved billboard placement while diagnosing serving separately.
	var screen_size := DisplayServer.screen_get_size()
	var density := maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0)
	var x := maxi(0, int((float(screen_size.x) / density - 320.0) * 0.5))
	var y := maxi(0, int(float(screen_size.y) / density * 0.223))
	_billboard_banner = AdView.new(_unit("banner"), AdSize.new(320, 50), AdPosition.custom(x, y))
	_billboard_banner.ad_listener.on_ad_loaded = func():
		diagnostic_status = "Banner loaded"
		_banner_retry_delay = 30.0
		_billboard_banner.show()
	_billboard_banner.ad_listener.on_ad_failed_to_load = func(error: LoadAdError):
		_record_error("Banner", error)
		_banner_retry.start(_banner_retry_delay)
		_banner_retry_delay = minf(_banner_retry_delay * 2.0, 300.0)
	diagnostic_status = "Requesting banner"
	_billboard_banner.load_ad(AdRequest.new())

func _record_error(kind: String, error: AdError) -> void:
	diagnostic_status = "%s: %s (%s, code %d)" % [kind, error.message, error.domain, error.code]
	push_warning(diagnostic_status)
	if error is LoadAdError and error.response_info != null:
		print("AdMob response ID: ", error.response_info.response_id)

func preload_ads() -> void:
	if not _initialized:
		return
	if _interstitial == null and not _interstitial_loading and not _unit("interstitial").is_empty():
		_interstitial_loading = true
		var callback := InterstitialAdLoadCallback.new()
		callback.on_ad_loaded = func(ad: InterstitialAd):
			_interstitial_loading = false
			_interstitial = ad
			ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = _interstitial_finished
			ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError):
				_record_error("Interstitial", error)
				_interstitial_finished()
			ad.full_screen_content_callback.on_ad_showed_full_screen_content = func():
				_rounds_since_ad = 0
				_last_ad_time_ms = Time.get_ticks_msec()
		callback.on_ad_failed_to_load = func(error: LoadAdError):
			_interstitial_loading = false
			_record_error("Interstitial", error)
		InterstitialAdLoader.new().load(_unit("interstitial"), AdRequest.new(), callback)
	if _rewarded == null and not _rewarded_loading and not _unit("rewarded").is_empty():
		_rewarded_loading = true
		var callback := RewardedAdLoadCallback.new()
		callback.on_ad_loaded = func(ad: RewardedAd):
			_rewarded_loading = false
			_rewarded = ad
			ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = _rewarded_finished
			ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError):
				_record_error("Rewarded", error)
				_rewarded_finished()
		callback.on_ad_failed_to_load = func(error: LoadAdError):
			_rewarded_loading = false
			_record_error("Rewarded", error)
		RewardedAdLoader.new().load(_unit("rewarded"), AdRequest.new(), callback)

func note_round_finished() -> void:
	_rounds_since_ad += 1

func should_show_interstitial() -> bool:
	return _rounds_since_ad >= 2 and Time.get_ticks_msec() - _last_ad_time_ms >= 60000

func show_interstitial_or_continue() -> void:
	if _showing:
		return
	if _interstitial != null and should_show_interstitial():
		_showing = true
		_interstitial.show()
	else:
		interstitial_closed.emit()

func _interstitial_finished() -> void:
	if _interstitial != null:
		_interstitial.destroy()
		_interstitial = null
	_showing = false
	interstitial_closed.emit()
	preload_ads()

func show_rewarded_continue() -> void:
	if _showing:
		return
	if _rewarded == null:
		status_message.emit("NO REWARD VIDEO AVAILABLE. TRY AGAIN LATER.")
		preload_ads()
		return
	_showing = true
	_reward_earned = false
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_reward): _reward_earned = true
	_rewarded.show(listener)

func _rewarded_finished() -> void:
	if _rewarded != null:
		_rewarded.destroy()
		_rewarded = null
	_showing = false
	if _reward_earned:
		_reward_earned = false
		rewarded_continue_earned.emit()
	preload_ads()

func _destroy_ads() -> void:
	for ad in [_billboard_banner, _interstitial, _rewarded]:
		if ad != null:
			ad.destroy()
	_billboard_banner = null
	_interstitial = null
	_rewarded = null
	if _banner_retry != null:
		_banner_retry.stop()

func _exit_tree() -> void:
	_destroy_ads()
