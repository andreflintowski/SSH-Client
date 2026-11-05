"""Verify the requested build and existing internal tester access after upload."""
import collections
import json
import os
import time
import urllib.error
import urllib.request


class Apple:
    def call(self, method, path, body=None):
        import jwt
        now = int(time.time())
        token = jwt.encode(
            {"iss": os.environ["ISSUER_ID"].strip(), "iat": now, "exp": now + 600,
             "aud": "appstoreconnect-v1"},
            os.environ["KEY_P8"], algorithm="ES256",
            headers={"kid": os.environ["KEY_ID"].strip()})
        request = urllib.request.Request(
            "https://api.appstoreconnect.apple.com/v1" + path, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Apple {method} {path}: HTTP {error.code}") from error


def exact_build(builds, number):
    matches = [b for b in builds if b["attributes"]["version"] == str(number)]
    if len(matches) > 1:
        raise RuntimeError("More than one build has the requested number")
    return matches[0] if matches else None


def internal_access(api, app_id, build):
    build_id = build["id"]
    if build["attributes"].get("usesNonExemptEncryption") is None:
        # Matches ITSAppUsesNonExemptEncryption=false in Runner/Info.plist.
        api.call("PATCH", f"/builds/{build_id}", {"data": {
            "type": "builds", "id": build_id,
            "attributes": {"usesNonExemptEncryption": False}}})
    groups = [g for g in api.call("GET", f"/apps/{app_id}/betaGroups?limit=200")["data"]
              if g["attributes"]["isInternalGroup"]]
    if not groups:
        raise RuntimeError("No existing internal tester group; no testers were invited or created")
    states = collections.Counter()
    for group in groups:
        group_id = group["id"]
        if not group["attributes"].get("hasAccessToAllBuilds"):
            assigned = api.call("GET", f"/betaGroups/{group_id}/builds?limit=200")["data"]
            if not any(b["id"] == build_id for b in assigned):
                api.call("POST", f"/betaGroups/{group_id}/relationships/builds", {
                    "data": [{"type": "builds", "id": build_id}]})
        testers = api.call("GET", f"/betaGroups/{group_id}/betaTesters?limit=200")["data"]
        states.update(t["attributes"].get("state", "UNKNOWN") for t in testers)
    detail = api.call("GET", f"/builds/{build_id}/buildBetaDetail")["data"]["attributes"]
    return {"build_id": build_id, "build_number": build["attributes"]["version"],
            "processing_state": build["attributes"]["processingState"],
            "internal_state": detail.get("internalBuildState"),
            "external_state": detail.get("externalBuildState"),
            "internal_groups": len(groups), "tester_states": dict(states),
            "accepted_or_installed_testers": states["ACCEPTED"] + states["INSTALLED"]}


def main():
    api = Apple()
    apps = api.call("GET", "/apps?filter[bundleId]=dev.andre.sshClient")["data"]
    if len(apps) != 1:
        raise RuntimeError("Expected exactly one SSH Andre app")
    app_id = apps[0]["id"]
    number = os.environ["BUILD_NUMBER"]
    result = None
    for _ in range(40):
        builds = api.call("GET", f"/builds?filter[app]={app_id}&filter[version]={number}&limit=200")["data"]
        build = exact_build(builds, number)
        if build:
            state = build["attributes"]["processingState"]
            print(f"::notice::Requested build {number} processingState={state}", flush=True)
            if state not in ("PROCESSING", "VALID"):
                raise RuntimeError(f"Apple rejected build {number}: {state}")
            if state == "VALID":
                result = internal_access(api, app_id, build)
                result.update({"app_id": app_id, "source_sha": os.environ["GITHUB_SHA"]})
                print("::notice::TestFlight status " + json.dumps(result), flush=True)
                if not result["accepted_or_installed_testers"]:
                    raise RuntimeError("Build processed, but existing groups have no accepted/installed testers")
                if result["internal_state"] == "IN_BETA_TESTING":
                    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                        summary.write("## Verified TestFlight build\n\n```json\n" +
                                      json.dumps(result, indent=2) + "\n```\n")
                    return
        else:
            print(f"::notice::Waiting for requested build {number} to appear", flush=True)
        time.sleep(20)
    raise RuntimeError("Timed out waiting for the requested build: " + json.dumps(result))


if __name__ == "__main__":
    main()
