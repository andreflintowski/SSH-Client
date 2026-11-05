"""Provision only SSH Andre signing assets; never revoke certificates or profiles."""
import base64
import json
import os
from pathlib import Path
import plistlib
from urllib.parse import quote

from verify_testflight import Apple


def certificate_for_csr(api, csr_pem):
    from cryptography import x509
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    csr = x509.load_pem_x509_csr(csr_pem.encode())
    if not csr.is_signature_valid:
        raise ValueError('Invalid CSR signature')
    public = csr.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
    for cert in api.call('GET', '/certificates?filter[certificateType]=DISTRIBUTION&limit=200')['data']:
        parsed = x509.load_der_x509_certificate(base64.b64decode(cert['attributes']['certificateContent']))
        if parsed.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo) == public:
            return cert
    return api.call('POST', '/certificates', {'data': {
        'type': 'certificates', 'attributes': {
            'certificateType': 'DISTRIBUTION', 'csrContent': csr_pem}}})['data']


def profile_for_certificate(api, cert_id):
    bundle = 'dev.andre.sshClient'
    bundles = api.call('GET', f'/bundleIds?filter[identifier]={bundle}')['data']
    matches = [b for b in bundles if b['attributes']['identifier'] == bundle]
    if len(matches) != 1:
        raise RuntimeError('Expected existing SSH Andre bundle ID')
    bundle_id = matches[0]['id']
    name = 'SSH Andre CI ' + cert_id
    for profile in api.call('GET', '/profiles?filter[name]=' + quote(name) + '&include=bundleId,certificates&limit=200')['data']:
        relationships = profile['relationships']
        if (profile['attributes']['profileState'] == 'ACTIVE'
                and profile['attributes']['profileType'] == 'IOS_APP_STORE'
                and relationships['bundleId']['data']['id'] == bundle_id
                and any(c['id'] == cert_id for c in relationships['certificates']['data'])):
            return profile
    return api.call('POST', '/profiles', {'data': {
        'type': 'profiles', 'attributes': {'name': name, 'profileType': 'IOS_APP_STORE'},
        'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_id}},
                          'certificates': {'data': [{'type': 'certificates', 'id': cert_id}]}}}})['data']


def main():
    api = Apple()
    csr = os.environ.get('SIGNING_CSR', '').strip()
    if csr:
        cert = certificate_for_csr(api, csr)
        output = Path(os.environ['RUNNER_TEMP']) / 'ssh-signing-public'
        output.mkdir(mode=0o700)
        (output / 'distribution.cer').write_bytes(base64.b64decode(cert['attributes']['certificateContent']))
        (output / 'certificate.json').write_text(json.dumps({'id': cert['id']}))
        print('::notice::SSH Andre CI distribution certificate prepared; no existing certificates revoked')
    else:
        cert_id = os.environ['IOS_DISTRIBUTION_CERT_ID']
        profile = profile_for_certificate(api, cert_id)
        content = base64.b64decode(profile['attributes']['profileContent'])
        folder = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / (profile['attributes']['uuid'] + '.mobileprovision')).write_bytes(content)
        options = {'method': 'app-store-connect', 'destination': 'upload',
                   'teamID': os.environ['TEAM_ID'], 'signingStyle': 'manual',
                   'signingCertificate': 'Apple Distribution',
                   'manageAppVersionAndBuildNumber': False,
                   'provisioningProfiles': {'dev.andre.sshClient': profile['attributes']['uuid']}}
        with open(Path(os.environ['RUNNER_TEMP']) / 'export.plist', 'wb') as output:
            plistlib.dump(options, output)
        print('::notice::SSH Andre App Store profile prepared for the CI certificate')


if __name__ == '__main__':
    main()
