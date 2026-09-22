package com.haseltonmediagroup.handball.services;

import android.app.Activity;
import android.util.Log;
import androidx.annotation.NonNull;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.games.PlayGames;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** Play Games v2 platform profile and highest-completed-court leaderboard. */
public final class HandballPlayGames extends GodotPlugin {
    private static final String TAG = "HandballPlayGames";
    private boolean signingIn;
    private boolean authenticated;

    public HandballPlayGames(Godot godot) { super(godot); }

    @NonNull @Override public String getPluginName() { return TAG; }

    @NonNull @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(
            new SignalInfo("authentication_changed", Boolean.class),
            new SignalInfo("player_changed", String.class),
            new SignalInfo("service_error", String.class)
        ));
    }

    private String resource(Activity activity, String name) {
        int id = activity.getResources().getIdentifier(name, "string", activity.getPackageName());
        return id == 0 ? "" : activity.getString(id).trim();
    }

    private boolean configured(Activity activity) {
        return !resource(activity, "game_services_project_id").isEmpty();
    }

    private void failure(String operation, Exception error) {
        Log.e(TAG, operation, error);
        String code = error instanceof ApiException
            ? " (code " + ((ApiException) error).getStatusCode() + ")" : "";
        emitSignal("service_error", operation + code + ". PLEASE TRY AGAIN.");
    }

    @UsedByGodot public void authenticate(boolean interactive) {
        Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (!configured(activity)) {
                emitSignal("service_error", "PLAY GAMES IS NOT CONFIGURED FOR THIS BUILD");
                return;
            }
            if (signingIn) return;
            signingIn = true;
            var client = PlayGames.getGamesSignInClient(activity);
            var task = interactive ? client.signIn() : client.isAuthenticated();
            task.addOnCompleteListener(activity, result -> {
                signingIn = false;
                authenticated = result.isSuccessful() && result.getResult().isAuthenticated();
                if (!authenticated) {
                    emitSignal("authentication_changed", false);
                    if (!result.isSuccessful()) failure("PLAY GAMES CONNECTION FAILED", result.getException());
                    else if (interactive) emitSignal("service_error", "PLAY GAMES SIGN-IN WAS NOT COMPLETED");
                    return;
                }
                PlayGames.getPlayersClient(activity).getCurrentPlayer()
                    .addOnSuccessListener(activity, player -> {
                        emitSignal("player_changed", player.getDisplayName());
                        emitSignal("authentication_changed", true);
                    })
                    .addOnFailureListener(activity, error -> {
                        emitSignal("player_changed", "PLAYER");
                        emitSignal("authentication_changed", true);
                        failure("COULD NOT LOAD PLAY GAMES PROFILE", error);
                    });
            });
        });
    }

    @UsedByGodot public void submit_highest_court(long completedCourts) {
        Activity activity = getActivity();
        if (activity == null || completedCourts < 1) return;
        activity.runOnUiThread(() -> {
            if (!authenticated || !configured(activity)) return;
            String leaderboard = resource(activity, "highest_court_leaderboard_id");
            if (leaderboard.isEmpty()) {
                emitSignal("service_error", "GLOBAL LEADERBOARD IS NOT CONFIGURED");
                return;
            }
            // submitScore queues delivery offline and Google keeps the highest score.
            PlayGames.getLeaderboardsClient(activity).submitScore(leaderboard, completedCourts);
        });
    }

    @UsedByGodot public void show_highest_court_leaderboard() {
        Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if (!authenticated) {
                emitSignal("service_error", "CONNECT TO PLAY GAMES FIRST");
                return;
            }
            String leaderboard = resource(activity, "highest_court_leaderboard_id");
            if (leaderboard.isEmpty()) {
                emitSignal("service_error", "GLOBAL LEADERBOARD IS NOT CONFIGURED");
                return;
            }
            PlayGames.getLeaderboardsClient(activity).getLeaderboardIntent(leaderboard)
                .addOnSuccessListener(activity, intent -> activity.startActivityForResult(intent, 9004))
                .addOnFailureListener(activity, error -> failure("COULD NOT OPEN GLOBAL LEADERBOARD", error));
        });
    }
}
