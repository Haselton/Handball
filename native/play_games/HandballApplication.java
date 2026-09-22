package com.haseltonmediagroup.handball.services;

import android.app.Application;
import com.google.android.gms.games.PlayGamesSdk;

public final class HandballApplication extends Application {
    @Override public void onCreate() {
        super.onCreate();
        int id = getResources().getIdentifier("game_services_project_id", "string", getPackageName());
        if (id != 0 && !getString(id).trim().isEmpty()) PlayGamesSdk.initialize(this);
    }
}
