"""Pin current runtime SDKs and the compatible Android build toolchain."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'android/build'


def replace_once(path, pattern, replacement):
    data, count = re.subn(pattern, lambda _: replacement, path.read_text(), flags=re.M)
    if count != 1:
        raise ValueError(f'Expected one matching setting in {path}: {pattern}')
    path.write_text(data)


def main():
    replace_once(BUILD / 'config.gradle', r"androidGradlePlugin\s*:\s*'[^']+'", "androidGradlePlugin: '8.13.2'")
    wrapper = BUILD / 'gradle/wrapper/gradle-wrapper.properties'
    replace_once(wrapper, r'^distributionUrl=.*$', r'distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-bin.zip')
    checksum = '20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78'
    data = wrapper.read_text()
    if re.search(r'^distributionSha256Sum=', data, re.M):
        replace_once(wrapper, r'^distributionSha256Sum=.*$', 'distributionSha256Sum=' + checksum)
    else:
        wrapper.write_text(data.rstrip() + '\ndistributionSha256Sum=' + checksum + '\n')
    shutil.copy(ROOT / 'ci/android_sdk.gradle', BUILD / 'handball_sdk.gradle')
    gradle = BUILD / 'build.gradle'
    line = 'apply from: "handball_sdk.gradle"'
    if line not in gradle.read_text():
        with gradle.open('a') as out:
            out.write('\n' + line + '\n')
    print('Pinned Ads SDK 1.5.0, Activity 1.13.0, AGP 8.13.2, Gradle 8.13')


if __name__ == '__main__':
    main()
