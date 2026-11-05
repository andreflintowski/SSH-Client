import unittest
from verify_testflight import exact_build, internal_access


def build(number="35"):
    return {"id": "requested", "attributes": {"version": number,
            "processingState": "VALID", "usesNonExemptEncryption": False}}


class FakeApple:
    def __init__(self, all_builds=True, groups=True):
        self.all_builds, self.groups, self.writes = all_builds, groups, []

    def call(self, method, path, body=None):
        if method != "GET":
            self.writes.append((method, path, body))
            return {}
        if "/apps/" in path:
            return {"data": [{"id": "internal", "attributes": {
                "isInternalGroup": True, "hasAccessToAllBuilds": self.all_builds}}] if self.groups else []}
        if "/builds?" in path:
            return {"data": [{"id": "older"}]}
        if "/betaTesters?" in path:
            return {"data": [{"attributes": {"state": "INSTALLED"}}]}
        if path.endswith("/buildBetaDetail"):
            return {"data": {"attributes": {"internalBuildState": "IN_BETA_TESTING",
                                             "externalBuildState": "READY_FOR_BETA_SUBMISSION"}}}
        raise AssertionError(path)


class TestFlightVerificationTests(unittest.TestCase):
    def test_never_substitutes_an_older_or_newer_build(self):
        self.assertIsNone(exact_build([build("25"), build("36")], "35"))
        requested = build("35")
        self.assertIs(exact_build([build("25"), requested], "35"), requested)

    def test_automatic_group_is_read_only(self):
        api = FakeApple()
        result = internal_access(api, "app", build())
        self.assertEqual(result["internal_state"], "IN_BETA_TESTING")
        self.assertEqual(result["accepted_or_installed_testers"], 1)
        self.assertEqual(api.writes, [])

    def test_only_requested_build_is_added_to_existing_group(self):
        api = FakeApple(all_builds=False)
        internal_access(api, "app", build())
        self.assertEqual(api.writes, [("POST", "/betaGroups/internal/relationships/builds",
                                      {"data": [{"type": "builds", "id": "requested"}]})])

    def test_missing_group_does_not_create_or_invite_people(self):
        api = FakeApple(groups=False)
        with self.assertRaisesRegex(RuntimeError, "No existing internal"):
            internal_access(api, "app", build())
        self.assertEqual(api.writes, [])


if __name__ == "__main__":
    unittest.main()
