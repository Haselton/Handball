"""Install real native services in Godot's generated Android template.

Production mode requires configured service IDs. Diagnostic mode uses Google test
ads and a separate Android package; it can compile without a Play Games project.
"""
import argparse
import json
import os
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ANDROID)
ET.register_namespace('tools', 'http://schemas.android.com/tools')
KEYS = {
    'PLAY_GAMES_APP_ID': 'play_games/app_id',
    'PLAY_GAMES_LEADERBOARD_ID': 'play_games/leaderboard_id',
    'ADMOB_BANNER_ID': 'ads/banner_id',
    'ADMOB_INTERSTITIAL_ID': 'ads/interstitial_id',
    'ADMOB_REWARDED_ID': 'ads/rewarded_id',
}
TEST_ADS = {
    'ads/banner_id': 'ca-app-pub-3940256099942544/6300978111',
    'ads/interstitial_id': 'ca-app-pub-3940256099942544/1033173712',
    'ads/rewarded_id': 'ca-app-pub-3940256099942544/5224354917',
}

def validate(values):
    errors = []
    for key in KEYS.values():
        value = values.get(key, '')
        pattern = (r'[1-9][0-9]+' if key == 'play_games/app_id' else
                   r'CgkI[A-Za-z0-9_-]+' if key == 'play_games/leaderboard_id' else
                   r'ca-app-pub-[0-9]{16}/[0-9]{10}')
        if not re.fullmatch(pattern, value) or '3940256099942544' in value:
            errors.append(key)
    if errors:
        raise ValueError('Production services missing or invalid: ' + ', '.join(errors))

def configure(root, mode, environ):
    project = root / 'project.godot'
    text = project.read_text()
    values = {}
    for env, key in KEYS.items():
        match = re.search(r'^' + re.escape(key) + r'=(.*)$', text, re.M)
        values[key] = environ.get(env, '').strip() or (json.loads(match[1]) if match else '')
    if mode == 'production':
        validate(values)
    else:
        values.update(TEST_ADS)
        # Never send diagnostics through a production OAuth/package pairing.
        values['play_games/app_id'] = ''
        values['play_games/leaderboard_id'] = ''
        text = text.replace('ca-app-pub-1051867648799965~7817745375', 'ca-app-pub-3940256099942544~3347511713')
    for key, value in values.items():
        text, count = re.subn(r'^' + re.escape(key) + r'=.*$', key + '=' + json.dumps(value), text, flags=re.M)
        if count != 1:
            raise ValueError('Expected exactly one project setting: ' + key)
    project.write_text(text)
    build = root / 'android/build'
    # Manually installed templates need the same import boundary as Godot's
    # template installer. Otherwise a later export imports its own output.
    (build / '.gdignore').touch()
    output = root / 'build'
    output.mkdir(exist_ok=True)
    (output / '.gdignore').touch()
    manifest_path = build / 'src/main/AndroidManifest.xml'
    tree = ET.parse(manifest_path)
    app = tree.getroot().find('application')
    app.set('{' + ANDROID + '}name', 'com.haseltonmediagroup.handball.services.HandballApplication')
    metadata = {
        'org.godotengine.plugin.v2.HandballPlayGames': 'com.haseltonmediagroup.handball.services.HandballPlayGames',
        'com.google.android.gms.games.SUPPRESS_GAME_PROFILE_CREATION': 'true',
    }
    if values['play_games/app_id']:
        metadata['com.google.android.gms.games.APP_ID'] = '@string/game_services_project_id'
    for name, value in metadata.items():
        matches = [item for item in app.findall('meta-data') if item.get('{' + ANDROID + '}name') == name]
        element = matches[0] if matches else ET.SubElement(app, 'meta-data')
        element.set('{' + ANDROID + '}name', name)
        element.set('{' + ANDROID + '}value', value)
    tree.write(manifest_path, encoding='utf-8', xml_declaration=True)
    strings = ET.Element('resources')
    for name, key in [('game_services_project_id', 'play_games/app_id'), ('highest_court_leaderboard_id', 'play_games/leaderboard_id')]:
        ET.SubElement(strings, 'string', {'name': name, 'translatable': 'false'}).text = values[key]
    resource_path = build / 'res/values/handball_services.xml'
    resource_path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(strings).write(resource_path, encoding='utf-8', xml_declaration=True)
    dest = build / 'src/main/java/com/haseltonmediagroup/handball/services'
    dest.mkdir(parents=True, exist_ok=True)
    for source in (root / 'native/play_games').glob('*.java'):
        shutil.copy2(source, dest)
    gradle = build / 'build.gradle'
    dependency = 'dependencies { implementation "com.google.android.gms:play-services-games-v2:22.1.0" }'
    if dependency not in gradle.read_text():
        with gradle.open('a') as file:
            file.write('\n' + dependency + '\n')
    if mode == 'diagnostic':
        preset = root / 'export_presets.cfg'
        data = preset.read_text().replace('com.haseltonmediagroup.handball"', 'com.haseltonmediagroup.handball.diagnostic"')
        data = data.replace('package/name="Handball"', 'package/name="Handball Diagnostics"')
        data = data.replace('architectures/x86_64=false', 'architectures/x86_64=true')
        preset.write_text(data)
    print('Native Play Games installed; service configuration mode: ' + mode)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['production', 'diagnostic'], default='production')
    args = parser.parse_args()
    try:
        configure(Path(__file__).resolve().parents[1], args.mode, os.environ)
    except ValueError as error:
        raise SystemExit(str(error))
