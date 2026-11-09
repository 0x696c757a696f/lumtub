# Makes the two keys of an APK Signature Scheme v3.2 hybrid signer pair:
# EC P-384 (classical) and ML-DSA-65 (post-quantum), each as PKCS #8 DER plus
# a self-signed X.509 certificate, into the folder given as the argument.
import datetime, sys
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import mldsa, ec
out = sys.argv[1]
def cert(key, cn, alg):
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn), x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Lumtub")])
    now = datetime.datetime(2026, 11, 9, tzinfo=datetime.timezone.utc)
    b = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
         .serial_number(x509.random_serial_number()).not_valid_before(now).not_valid_after(now + datetime.timedelta(days=36500)))
    return b.sign(key, alg)
pq = mldsa.MLDSA65PrivateKey.generate()
cl = ec.generate_private_key(ec.SECP384R1())
for tag, key, alg in (("pqc", pq, None), ("classical", cl, hashes.SHA384())):
    c = cert(key, "Lumtub " + tag, alg)
    der_key = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    der_cert = c.public_bytes(serialization.Encoding.DER)
    open(f"{out}/hybrid-{tag}.pk8", "wb").write(der_key)
    open(f"{out}/hybrid-{tag}.x509.der", "wb").write(der_cert)
    print(tag, c.signature_algorithm_oid, c.fingerprint(hashes.SHA256()).hex(":").upper())
