import importlib.util
import os
from pathlib import Path
import re
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('services', ROOT / 'ci/configure_services.py')
services = importlib.util.module_from_spec(spec)
spec.loader.exec_module(services)

class ServicesBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['project.godot', 'export_presets.cfg']:
            shutil.copy(ROOT / name, self.root / name)
        shutil.copytree(ROOT / 'native', self.root / 'native')
        build = self.root / 'android/build'
        (build / 'src/main').mkdir(parents=True)
        (build / 'src/main/AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application /></manifest>')
        (build / 'build.gradle').write_text('plugins {}\n')
        self.env = {
            'PLAY_GAMES_APP_ID': '123456789012',
            'PLAY_GAMES_LEADERBOARD_ID': 'CgkITestLeaderboard',
            'ADMOB_INTERSTITIAL_ID': 'ca-app-pub-1051867648799965/1111111111',
            'ADMOB_REWARDED_ID': 'ca-app-pub-1051867648799965/2222222222',
        }

    def test_missing_configuration_blocks_production_without_mutation(self):
        project = self.root / 'project.godot'
        # Explicitly remove the ID from the fixture; the app now has real IDs.
        text, count = re.subn(r'^play_games/app_id=.*$', 'play_games/app_id=""', project.read_text(), flags=re.M)
        self.assertEqual(count, 1)
        project.write_text(text)
        original = (self.root / 'project.godot').read_bytes()
        with self.assertRaisesRegex(ValueError, 'play_games/app_id'):
            services.configure(self.root, 'production', {})
        self.assertEqual(original, (self.root / 'project.godot').read_bytes())

    def test_test_ads_are_rejected_in_production(self):
        self.env['ADMOB_REWARDED_ID'] = services.TEST_ADS['ads/rewarded_id']
        with self.assertRaisesRegex(ValueError, 'ads/rewarded_id'):
            services.configure(self.root, 'production', self.env)

    def test_native_registration_resource_ids_and_sources_are_packaged(self):
        services.configure(self.root, 'production', self.env)
        services.configure(self.root, 'production', self.env)
        build = self.root / 'android/build'
        tree = ET.parse(build / 'src/main/AndroidManifest.xml')
        meta = {item.get('{%s}name' % services.ANDROID): item.get('{%s}value' % services.ANDROID) for item in tree.findall('./application/meta-data')}
        self.assertEqual(meta['com.google.android.gms.games.APP_ID'], '@string/game_services_project_id')
        self.assertIn('org.godotengine.plugin.v2.HandballPlayGames', meta)
        resources = ET.parse(build / 'res/values/handball_services.xml')
        values = {item.get('name'): item.text for item in resources.getroot()}
        self.assertEqual(values['game_services_project_id'], self.env['PLAY_GAMES_APP_ID'])
        self.assertEqual(values['highest_court_leaderboard_id'], self.env['PLAY_GAMES_LEADERBOARD_ID'])
        self.assertTrue((build / 'src/main/java/com/haseltonmediagroup/handball/services/HandballPlayGames.java').is_file())
        self.assertEqual((build / 'build.gradle').read_text().count('play-services-games-v2'), 1)
        self.assertNotIn('.diagnostic', (self.root / 'export_presets.cfg').read_text())

    def test_diagnostic_is_separate_package_with_only_test_ads(self):
        services.configure(self.root, 'diagnostic', self.env)
        text = (self.root / 'project.godot').read_text()
        self.assertIn('play_games/app_id=""', text)
        self.assertNotIn('ca-app-pub-1051867648799965', text)
        self.assertIn('com.haseltonmediagroup.handball.diagnostic', (self.root / 'export_presets.cfg').read_text())

if __name__ == '__main__':
    unittest.main()
