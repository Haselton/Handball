"""Compile the real bridge against fakes that model Task's onStop removal.

This is a host regression test, not a substitute for Play-signed device testing.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "android/app/Activity.java": """
package android.app;
import java.util.*;
public class Activity {
    public boolean destroyed;
    public final List<Runnable> stopActions = new ArrayList<>();
    public void runOnUiThread(Runnable r) { r.run(); }
    public void stop() { for (Runnable r : new ArrayList<>(stopActions)) r.run(); stopActions.clear(); }
    public boolean isDestroyed() { return destroyed; }
    public boolean isFinishing() { return destroyed; }
    public android.content.res.Resources getResources() { return new android.content.res.Resources(); }
    public String getPackageName() { return "com.haseltonmediagroup.handball"; }
    public String getString(int id) { return "configured"; }
    public void startActivityForResult(Object intent, int code) {}
}
""",
    "android/content/res/Resources.java": """
package android.content.res;
public class Resources { public int getIdentifier(String n, String t, String p) { return 1; } }
""",
    "android/util/Log.java": """
package android.util;
public class Log { public static int e(String t, String m, Throwable e) { return 0; } }
""",
    "androidx/annotation/NonNull.java": """
package androidx.annotation;
public @interface NonNull {}
""",
    "com/google/android/gms/common/api/ApiException.java": """
package com.google.android.gms.common.api;
public class ApiException extends Exception { public int getStatusCode() { return 10; } }
""",
    "org/godotengine/godot/Godot.java": """
package org.godotengine.godot;
public class Godot {
    public android.app.Activity activity = new android.app.Activity();
    public final java.util.List<String> signals = new java.util.ArrayList<>();
}
""",
    "org/godotengine/godot/plugin/GodotPlugin.java": """
package org.godotengine.godot.plugin;
import org.godotengine.godot.Godot;
public class GodotPlugin {
    protected final Godot godot;
    public GodotPlugin(Godot g) { godot = g; }
    public android.app.Activity getActivity() { return godot.activity; }
    public String getPluginName() { return ""; }
    public java.util.Set<SignalInfo> getPluginSignals() { return null; }
    public void emitSignal(String name, Object... args) { godot.signals.add(name + ":" + args[0]); }
}
""",
    "org/godotengine/godot/plugin/SignalInfo.java": """
package org.godotengine.godot.plugin;
public class SignalInfo { public SignalInfo(String name, Class<?>... args) {} }
""",
    "org/godotengine/godot/plugin/UsedByGodot.java": """
package org.godotengine.godot.plugin;
public @interface UsedByGodot {}
""",
    "com/google/android/gms/tasks/Task.java": """
package com.google.android.gms.tasks;
import java.util.*;
import java.util.function.Consumer;
import android.app.Activity;
public class Task<T> {
    private final List<Runnable> callbacks = new ArrayList<>();
    private T value;
    private Exception error;
    public boolean isSuccessful() { return error == null; }
    public T getResult() { return value; }
    public Exception getException() { return error; }
    private Task<T> add(Activity a, Runnable callback) {
        callbacks.add(callback);
        if (a != null) a.stopActions.add(() -> callbacks.remove(callback));
        return this;
    }
    public Task<T> addOnCompleteListener(Consumer<Task<T>> c) { return add(null, () -> c.accept(this)); }
    public Task<T> addOnCompleteListener(Activity a, Consumer<Task<T>> c) { return add(a, () -> c.accept(this)); }
    public Task<T> addOnSuccessListener(Consumer<T> c) { return add(null, () -> { if (isSuccessful()) c.accept(value); }); }
    public Task<T> addOnSuccessListener(Activity a, Consumer<T> c) { return add(a, () -> { if (isSuccessful()) c.accept(value); }); }
    public Task<T> addOnFailureListener(Consumer<Exception> c) { return add(null, () -> { if (!isSuccessful()) c.accept(error); }); }
    public Task<T> addOnFailureListener(Activity a, Consumer<Exception> c) { return add(a, () -> { if (!isSuccessful()) c.accept(error); }); }
    public void complete(T result, Exception failure) {
        value = result; error = failure;
        for (Runnable r : new ArrayList<>(callbacks)) r.run();
        callbacks.clear();
    }
}
""",
    "com/google/android/gms/games/PlayGames.java": """
package com.google.android.gms.games;
import android.app.Activity;
import com.google.android.gms.tasks.Task;
public class PlayGames {
    public static int signInCalls;
    public static Task<Auth> auth;
    public static Task<Player> player;
    public static class Auth {
        private final boolean authenticated;
        public Auth(boolean b) { authenticated = b; }
        public boolean isAuthenticated() { return authenticated; }
    }
    public static class Player { public String getDisplayName() { return "Test Player"; } }
    public static class SignInClient {
        public Task<Auth> signIn() { signInCalls++; return auth = new Task<>(); }
        public Task<Auth> isAuthenticated() { return signIn(); }
    }
    public static class PlayersClient { public Task<Player> getCurrentPlayer() { return player = new Task<>(); } }
    public static class LeaderboardsClient {
        public void submitScore(String id, long score) {}
        public Task<Object> getLeaderboardIntent(String id) { return new Task<>(); }
    }
    public static SignInClient getGamesSignInClient(Activity a) { return new SignInClient(); }
    public static PlayersClient getPlayersClient(Activity a) { return new PlayersClient(); }
    public static LeaderboardsClient getLeaderboardsClient(Activity a) { return new LeaderboardsClient(); }
}
""",
    "LifecycleTest.java": """
import com.haseltonmediagroup.handball.services.HandballPlayGames;
import com.google.android.gms.games.PlayGames;
import org.godotengine.godot.Godot;
public class LifecycleTest {
    private static void check(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
    public static void main(String[] args) {
        Godot g = new Godot();
        HandballPlayGames plugin = new HandballPlayGames(g);
        String test = args[0];
        plugin.authenticate(true);
        if (test.equals("retry_after_stop")) {
            g.activity.stop();
            PlayGames.auth.complete(null, new Exception("network"));
            plugin.authenticate(true);
            check(PlayGames.signInCalls == 2, "Sign-in stays latched after onStop; retry ignored");
            check(g.signals.contains("authentication_changed:false"), "Missing failed authentication signal");
        } else if (test.equals("success_after_stop")) {
            g.activity.stop();
            PlayGames.auth.complete(new PlayGames.Auth(true), null);
            check(PlayGames.player != null, "Stopped authentication never completes");
            PlayGames.player.complete(new PlayGames.Player(), null);
            check(g.signals.contains("authentication_changed:true"), "Successful authentication was lost");
        } else if (test.equals("profile_after_stop") || test.equals("profile_failure_after_stop")) {
            PlayGames.auth.complete(new PlayGames.Auth(true), null);
            g.activity.stop();
            boolean failed = test.equals("profile_failure_after_stop");
            PlayGames.player.complete(failed ? null : new PlayGames.Player(), failed ? new Exception("profile") : null);
            check(g.signals.contains("authentication_changed:true"), "Profile callback lost authentication state");
            check(g.signals.contains("player_changed:" + (failed ? "PLAYER" : "Test Player")), "Missing player signal");
        } else if (test.equals("duplicate_taps")) {
            plugin.authenticate(true);
            check(PlayGames.signInCalls == 1, "Duplicate tap started another pending sign-in");
            PlayGames.auth.complete(new PlayGames.Auth(false), null);
            plugin.authenticate(true);
            check(PlayGames.signInCalls == 2, "Cancelled sign-in cannot retry");
        } else if (test.equals("destroyed_activity")) {
            g.activity.stop(); g.activity.destroyed = true;
            PlayGames.auth.complete(new PlayGames.Auth(true), null);
            check(PlayGames.player == null && g.signals.isEmpty(), "Callback used a destroyed activity");
        } else if (test.equals("destroyed_profile")) {
            PlayGames.auth.complete(new PlayGames.Auth(true), null);
            g.activity.stop(); g.activity.destroyed = true;
            PlayGames.player.complete(new PlayGames.Player(), null);
            check(g.signals.isEmpty(), "Profile callback used a destroyed activity");
        } else throw new AssertionError("Unknown scenario");
        System.out.println("PASS " + test);
    }
}
""",
}


class PlayGamesLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.build = Path(cls.temp.name)
        java_home = os.environ.get("JAVA_HOME", "/usr/lib/jvm/java-17-openjdk-amd64")
        cls.java = shutil.which("java") or str(Path(java_home) / "bin/java")
        paths = []
        for name, source in SOURCES.items():
            path = cls.build / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
            paths.append(str(path))
        paths.append(str(ROOT / "native/play_games/HandballPlayGames.java"))
        subprocess.run([cls.java, "com.sun.tools.javac.Main", "-d", str(cls.build), *paths], check=True)

    def test_lifecycle(self):
        for scenario in ("retry_after_stop", "success_after_stop", "profile_after_stop",
                         "profile_failure_after_stop", "duplicate_taps", "destroyed_activity",
                         "destroyed_profile"):
            with self.subTest(scenario=scenario):
                result = subprocess.run([self.java, "-cp", str(self.build), "LifecycleTest", scenario],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
