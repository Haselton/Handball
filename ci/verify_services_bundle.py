"""Check the exported AAB actually contains the Android classes and registrations."""
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as bundle:
    manifests = b'\n'.join(bundle.read(name) for name in bundle.namelist() if name.endswith('/manifest/AndroidManifest.xml'))
    dex = b'\n'.join(bundle.read(name) for name in bundle.namelist() if name.endswith('.dex'))
    for registration in [b'org.godotengine.plugin.v2.HandballPlayGames', b'org.godotengine.plugin.v2.PoingGodotAdMobAdView']:
        assert registration in manifests, 'Missing native registration: ' + registration.decode()
    for descriptor in [b'Lcom/haseltonmediagroup/handball/services/HandballPlayGames;', b'Lcom/haseltonmediagroup/handball/services/HandballApplication;', b'Lcom/google/android/gms/games/PlayGames;', b'Lcom/poingstudios/godot/admob/ads/PoingGodotAdMobAdView;']:
        assert descriptor in dex, 'Missing Android class: ' + descriptor.decode()
print('AAB contains Play Games and AdMob native services.')
