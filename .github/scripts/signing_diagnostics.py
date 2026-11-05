"""Read-only Apple signing/build checks; redact distribution log errors."""
import collections
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from verify_testflight import Apple, exact_build


def distribution_errors():
    emitted = 0
    for folder in Path(tempfile.gettempdir()).glob('Runner_*.xcdistributionlogs'):
        for file in folder.rglob('*.log'):
            for line in file.read_text(errors='replace').splitlines():
                if not re.search(r'error|failed|expected results|no profiles|cloud.sign', line, re.I):
                    continue
                if re.search(r'authorization|private.key|bearer|password|token', line, re.I):
                    continue
                line = re.sub(r'[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', '[REDACTED_JWT]', line)
                line = re.sub(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', '[REDACTED_EMAIL]', line)
                print(f'::notice::Distribution diagnostic {file.name}: {line[:1200]}')
                emitted += 1
                if emitted >= 100:
                    return


def main():
    distribution_errors()
    api = Apple()
    report = {}
    try:
        apps = api.call('GET', '/apps?filter[bundleId]=dev.andre.sshClient')['data']
        if len(apps) != 1:
            raise RuntimeError('Expected exactly one SSH Andre app')
        app = apps[0]['id']
        builds = api.call('GET', f'/builds?filter[app]={app}&sort=-uploadedDate&limit=20')['data']
        report['latest_builds'] = [{k: b['attributes'].get(k) for k in
                                   ['version', 'processingState', 'uploadedDate']} for b in builds]
        number = os.environ.get('BUILD_NUMBER', '')
        if number:
            matches = api.call('GET', f'/builds?filter[app]={app}&filter[version]={number}&limit=200')['data']
            requested = exact_build(matches, number)
            report['requested_build_number'] = number
            report['requested_build_present'] = requested is not None
            if requested:
                report['requested_build_processing'] = requested['attributes']['processingState']
                report['requested_build_beta_detail'] = api.call('GET', f"/builds/{requested['id']}/buildBetaDetail")['data']['attributes']
        versions = api.call('GET', f'/apps/{app}/appStoreVersions?limit=200')['data']
        report['app_store_versions'] = [{k: v['attributes'].get(k) for k in
                                       ['versionString', 'appStoreState', 'platform']} for v in versions]
    except Exception as error:
        report['app_error'] = str(error)
    try:
        certs = api.call('GET', '/certificates?limit=200')['data']
        report['certificate_types'] = dict(collections.Counter(c['attributes'].get('certificateType') for c in certs))
        report['certificate_expiration_dates'] = [c['attributes'].get('expirationDate') for c in certs]
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        import base64
        configured = os.environ.get('TEAM_ID', '').strip()
        teams = set()
        for cert in certs:
            content = cert['attributes'].get('certificateContent')
            if content:
                parsed = x509.load_der_x509_certificate(base64.b64decode(content))
                teams.update(a.value for a in parsed.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME))
        report['configured_team_shape_valid'] = bool(re.fullmatch(r'[A-Z0-9]{10}', configured))
        report['configured_team_matches_certificate_team'] = configured in teams
    except Exception as error:
        report['certificate_error'] = str(error)
    try:
        data = api.call('GET', '/profiles?limit=200&include=bundleId,certificates')
        included = {i['id']: i for i in data.get('included', [])}
        profiles = []
        for profile in data['data']:
            bundle_id = profile['relationships']['bundleId']['data']['id']
            if included.get(bundle_id, {}).get('attributes', {}).get('identifier') == 'dev.andre.sshClient':
                profiles.append({k: profile['attributes'].get(k) for k in
                                 ['profileType', 'profileState', 'expirationDate']})
        report['ssh_profiles'] = profiles
    except Exception as error:
        report['profile_error'] = str(error)
    print('::notice::Apple signing diagnostics ' + json.dumps(report))
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write('## Read-only signing diagnostics\n\n```json\n' + json.dumps(report, indent=2) + '\n```\n')


if __name__ == '__main__':
    main()
