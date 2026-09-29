extends SceneTree

class RetryProbe extends AdService:
	var retry_calls := 0
	func preload_ads() -> void:
		retry_calls += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ads := AdService.new()
	root.add_child(ads)
	ads._set_ad_status("Banner", "No fill")
	ads._set_ad_status("Rewarded", "No fill")
	ads._set_ad_status("Rewarded", "Ready")
	assert(ads.diagnostic_status.contains("Banner: No fill"), "Rewarded success must not conceal banner failure")
	assert(ads.diagnostic_status.contains("Rewarded: Ready"), "A successful load must clear that format's stale error")
	ads._initialized = true
	ads._schedule_fullscreen_retry("Rewarded")
	ads._schedule_fullscreen_retry("Interstitial")
	ads.preload_ads()
	assert(not ads._rewarded_loading and not ads._interstitial_loading, "Gameplay preload must respect retry backoff")
	ads._reset_fullscreen_retry("Rewarded")
	ads._rewarded_loading = true
	var messages: Array[String] = []
	ads.status_message.connect(func(message: String): messages.append(message))
	ads.show_rewarded_continue()
	assert(messages[-1].contains("LOADING"), "An in-flight ad must be described as loading, not unavailable")
	ads._rewarded_loading = false
	ads._schedule_fullscreen_retry("Rewarded")
	assert(ads._fullscreen_retries["Rewarded"].wait_time == 30.0, "Success must reset retry delay")
	assert(ads._fullscreen_retry_pending("Interstitial"), "Resetting one format must preserve the other's retry")
	ads._destroy_ads()
	assert(not ads._fullscreen_retry_pending("Rewarded") and not ads._fullscreen_retry_pending("Interstitial"), "Privacy reset must stop pending retries")
	ads.queue_free()
	var probe := RetryProbe.new()
	root.add_child(probe)
	probe._schedule_fullscreen_retry("Rewarded")
	probe._fullscreen_retries["Rewarded"].start(0.01)
	await create_timer(0.05).timeout
	assert(probe.retry_calls == 1, "A failed load must retry without another gameplay action")
	for attempt in range(8):
		probe._set_ad_status("Rewarded", "No fill")
		probe._schedule_fullscreen_retry("Rewarded")
	assert(probe._fullscreen_retries["Rewarded"].wait_time == 300.0, "Repeated failures must cap backoff at five minutes")
	assert(probe.get_child_count() == 1, "Retries must reuse one timer per format")
	probe._destroy_ads()
	probe.queue_free()
	await process_frame
	await process_frame
	# The SDK can construct desktop mock nodes before SceneTree exists.
	# They have no parent to free them when this headless test exits.
	var mocks = load("res://addons/admob/internal/mock/mock_admob_factory.gd")
	for mock in mocks._mocks.values():
		if is_instance_valid(mock) and mock is Node and mock.get_parent() == null:
			mock.free()
	mocks._mocks.clear()
	print("Handball ad recovery checks passed")
	quit(0)
