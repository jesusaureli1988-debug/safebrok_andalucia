import io
import plistlib
import unittest
import zipfile
from check_ios_privacy_manifest import check_ipa


class PrivacyManifestTests(unittest.TestCase):
    def ipa(self, name, contents):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as archive:
            archive.writestr(name, contents)
        data.seek(0)
        return data

    def test_sdk_manifest(self):
        check_ipa(self.ipa(
            'Payload/Runner.app/package_info_plus_privacy.bundle/PrivacyInfo.xcprivacy',
            plistlib.dumps({'NSPrivacyTracking': False})))

    def test_app_manifest_is_not_sdk_manifest(self):
        with self.assertRaises(ValueError):
            check_ipa(self.ipa('Payload/Runner.app/PrivacyInfo.xcprivacy',
                               plistlib.dumps({'NSPrivacyTracking': False})))

    def test_invalid_sdk_manifest(self):
        with self.assertRaises(ValueError):
            check_ipa(self.ipa(
                'Payload/Runner.app/package_info_plus_privacy.bundle/PrivacyInfo.xcprivacy',
                plistlib.dumps({})))


if __name__ == '__main__':
    unittest.main()
