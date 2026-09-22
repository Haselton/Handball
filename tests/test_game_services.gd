extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.play_games_service.pending_rank_score = 0
	game.play_games_service.submit_progress(1, 4, 999)
	assert(game.play_games_service.pending_rank_score == 0, "Court 1 is not completed yet")
	game.play_games_service.submit_progress(5, 1, 28)
	assert(game.play_games_service.pending_rank_score == 4, "Leaderboard must count completed courts")
	game.play_games_service.submit_progress(2, 9, 9999)
	assert(game.play_games_service.pending_rank_score == 4, "Lower progress must not overwrite the best")
	var reloaded = PlayGamesService.new()
	root.add_child(reloaded)
	assert(reloaded.pending_rank_score == 4, "Offline progress must survive a new service instance")
	game.state = game.GameState.LOST
	game.score = 28
	game.ad_service._reward_earned = false
	game.ad_service._rewarded_finished()
	assert(game.state == game.GameState.LOST, "Dismissal without earning must not save a rally")
	game.ad_service._reward_earned = true
	game.ad_service._rewarded_finished()
	assert(game.state == game.GameState.READY, "An earned reward must resume the rally")
	assert(game.score == 28, "A saved rally must retain its score")
	game.state = game.GameState.LOST
	game._on_new_rally_pressed()
	assert(game.score == 0, "No-fill must not block a new rally")
	print("Handball service gameplay checks passed")
	quit(0)
