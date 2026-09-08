//! Mac App Store receipt validation.
//!
//! App Attest does not exist below macOS 27, so a Mac on 15 or 26 cannot prove
//! anything through the Secure Enclave. Every Roam copy ships through
//! `app-store-connect`, which means every one carries a receipt that Apple
//! signed, and that receipt is the strongest integrity proof the platform
//! offers there.
//!
//! What it proves is narrower than an attestation, and the difference matters:
//! a receipt is a static file, so verifying it establishes that a genuine App
//! Store receipt for this bundle exists, not that this request came from the
//! Mac it was issued to. Binding one receipt to one install id (see
//! `receipt_fingerprint`) is what caps a copied receipt to a single
//! conversation.
//!
//! The payload is Apple's, and is not self-describing: attribute numbering and
//! the CMS signing convention are spelled out where they are read.

use chrono::{DateTime, Utc};
use cms::content_info::ContentInfo;
use cms::signed_data::{SignedData, SignerInfo};
use der::{Decode, Encode, Tag};
use sha2_digest10::{Digest, Sha256};
use x509_cert::Certificate;

/// Apple Root CA, from <https://www.apple.com/appleca/AppleIncRootCertificate.cer>.
/// RSA, valid to 2035. This is not the App Attest root; receipts chain to the
/// general Apple root instead.
const APPLE_ROOT_CA_DER: &[u8] = include_bytes!("apple_root_ca.der");

/// Receipt attribute numbers, from Apple's receipt field reference. The payload
/// is a `SET OF SEQUENCE { type INTEGER, version INTEGER, value OCTET STRING }`
/// and carries no field names, so the numbers are the only handle on it.
const ATTR_BUNDLE_ID: u32 = 2;
const ATTR_APP_VERSION: u32 = 3;
const ATTR_OPAQUE_VALUE: u32 = 4;
const ATTR_SHA1_HASH: u32 = 5;

const OID_SHA256: &str = "2.16.840.1.101.3.4.2.1";
const OID_SHA1: &str = "1.3.14.3.2.26";
const OID_MESSAGE_DIGEST: &str = "1.2.840.113549.1.9.4";

const OID_SHA256_WITH_RSA: &str = "1.2.840.113549.1.1.11";
const OID_SHA1_WITH_RSA: &str = "1.2.840.113549.1.1.5";
/// Names the key algorithm and no digest, so the signerInfo supplies the hash.
const OID_RSA_ENCRYPTION: &str = "1.2.840.113549.1.1.1";

#[derive(Debug, thiserror::Error)]
pub enum ReceiptError {
    #[error("malformed receipt: {0}")]
    Malformed(String),
    #[error("receipt certificate chain rejected: {0}")]
    Chain(String),
    #[error("receipt signature is not valid")]
    BadSignature,
    #[error("receipt is for {found}, which is not an accepted bundle id")]
    BundleMismatch { found: String },
}

#[derive(Debug, Clone)]
pub struct VerifiedReceipt {
    pub bundle_id: String,
    pub app_version: String,
    /// Stable per-receipt identifier, so one purchased copy maps to one
    /// install. Derived rather than stored, so the receipt itself never lands
    /// in the database.
    pub fingerprint: Vec<u8>,
}

/// Verifies an App Store receipt and returns what it claims.
pub fn verify_receipt(
    receipt_der: &[u8],
    allowed_bundle_ids: &[String],
    now: DateTime<Utc>,
) -> Result<VerifiedReceipt, ReceiptError> {
    let content_info = ContentInfo::from_der(receipt_der)
        .map_err(|e| ReceiptError::Malformed(format!("not a CMS container: {e}")))?;
    let signed_data = content_info
        .content
        .decode_as::<SignedData>()
        .map_err(|e| ReceiptError::Malformed(format!("not CMS SignedData: {e}")))?;

    let payload = signed_data
        .encap_content_info
        .econtent
        .as_ref()
        .ok_or_else(|| ReceiptError::Malformed("receipt carries no payload".into()))?
        .value()
        .to_vec();

    let certificates = collect_certificates(&signed_data)?;
    let signer = verify_chain(&certificates, now)?;

    let signer_info = signed_data
        .signer_infos
        .0
        .as_slice()
        .first()
        .ok_or_else(|| ReceiptError::Malformed("receipt has no signer".into()))?;
    verify_signature(signer_info, &signer, &payload)?;

    parse_payload(&payload, allowed_bundle_ids)
}

fn collect_certificates(signed_data: &SignedData) -> Result<Vec<Certificate>, ReceiptError> {
    let set = signed_data
        .certificates
        .as_ref()
        .ok_or_else(|| ReceiptError::Chain("receipt carries no certificates".into()))?;
    let mut certificates = Vec::new();
    for choice in set.0.iter() {
        if let cms::cert::CertificateChoices::Certificate(certificate) = choice {
            certificates.push(certificate.clone());
        }
    }
    if certificates.is_empty() {
        return Err(ReceiptError::Chain(
            "receipt carries no X.509 certificate".into(),
        ));
    }
    Ok(certificates)
}

/// Walks the bundled certificates up to the pinned Apple root and returns the
/// leaf that signed the receipt.
///
/// The set arrives unordered, so the leaf is the one no other certificate was
/// issued by, and each link is then resolved by issuer name.
fn verify_chain(
    certificates: &[Certificate],
    now: DateTime<Utc>,
) -> Result<Certificate, ReceiptError> {
    let root = Certificate::from_der(APPLE_ROOT_CA_DER)
        .map_err(|e| ReceiptError::Chain(format!("embedded Apple root is unreadable: {e}")))?;

    let leaf = certificates
        .iter()
        .find(|candidate| {
            !certificates
                .iter()
                .any(|other| other.tbs_certificate.issuer == candidate.tbs_certificate.subject)
        })
        .ok_or_else(|| ReceiptError::Chain("certificates form a cycle".into()))?
        .clone();

    let mut current = leaf.clone();
    for _ in 0..4 {
        check_validity(&current, now)?;

        if current.tbs_certificate.issuer == root.tbs_certificate.subject {
            verify_certificate_signature(&current, &root)?;
            return Ok(leaf);
        }

        let issuer = certificates
            .iter()
            .find(|candidate| candidate.tbs_certificate.subject == current.tbs_certificate.issuer)
            .ok_or_else(|| ReceiptError::Chain("chain does not reach the Apple root".into()))?
            .clone();
        verify_certificate_signature(&current, &issuer)?;
        current = issuer;
    }

    Err(ReceiptError::Chain("chain is longer than expected".into()))
}

fn check_validity(certificate: &Certificate, now: DateTime<Utc>) -> Result<(), ReceiptError> {
    let validity = &certificate.tbs_certificate.validity;
    let not_before = validity.not_before.to_unix_duration().as_secs() as i64;
    let not_after = validity.not_after.to_unix_duration().as_secs() as i64;
    let now = now.timestamp();
    if now < not_before || now > not_after {
        return Err(ReceiptError::Chain(
            "a certificate in the receipt chain is outside its validity window".into(),
        ));
    }
    Ok(())
}

fn verify_certificate_signature(
    certificate: &Certificate,
    issuer: &Certificate,
) -> Result<(), ReceiptError> {
    let tbs = certificate
        .tbs_certificate
        .to_der()
        .map_err(|e| ReceiptError::Chain(format!("could not re-encode tbsCertificate: {e}")))?;
    let signature = certificate
        .signature
        .as_bytes()
        .ok_or_else(|| ReceiptError::Chain("signature is not octet aligned".into()))?;
    let algorithm = certificate.signature_algorithm.oid.to_string();
    let key = issuer
        .tbs_certificate
        .subject_public_key_info
        .to_der()
        .map_err(|e| ReceiptError::Chain(format!("could not re-encode issuer key: {e}")))?;

    verify_rsa(&key, &algorithm, &algorithm, &tbs, signature)
        .map_err(|_| ReceiptError::Chain("a certificate signature does not verify".into()))
}

/// Checks the CMS signature.
///
/// When signed attributes are present, CMS signs the DER re-encoding of that
/// attribute set rather than the payload, and the payload is bound in through
/// the `messageDigest` attribute. Verifying the payload directly would accept a
/// receipt whose attributes were swapped.
fn verify_signature(
    signer_info: &SignerInfo,
    signer: &Certificate,
    payload: &[u8],
) -> Result<(), ReceiptError> {
    let key = signer
        .tbs_certificate
        .subject_public_key_info
        .to_der()
        .map_err(|e| ReceiptError::Malformed(format!("could not re-encode signer key: {e}")))?;
    let digest_oid = signer_info.digest_alg.oid.to_string();
    let signature_oid = signer_info.signature_algorithm.oid.to_string();
    let signature = signer_info.signature.as_bytes();

    let Some(signed_attrs) = signer_info.signed_attrs.as_ref() else {
        return verify_rsa(&key, &signature_oid, &digest_oid, payload, signature)
            .map_err(|_| ReceiptError::BadSignature);
    };

    let expected = digest(&digest_oid, payload)?;
    let declared = signed_attrs
        .iter()
        .find(|attr| attr.oid.to_string() == OID_MESSAGE_DIGEST)
        .and_then(|attr| attr.values.get(0))
        .map(|value| value.value().to_vec())
        .ok_or_else(|| {
            ReceiptError::Malformed("signed attributes carry no messageDigest".into())
        })?;
    if declared != expected {
        return Err(ReceiptError::BadSignature);
    }

    // The attributes are carried with an implicit [0] tag and signed as a SET.
    let mut signed = signed_attrs
        .to_der()
        .map_err(|e| ReceiptError::Malformed(format!("could not re-encode attributes: {e}")))?;
    signed[0] = Tag::Set.octet();

    verify_rsa(&key, &signature_oid, &digest_oid, &signed, signature)
        .map_err(|_| ReceiptError::BadSignature)
}

fn digest(oid: &str, data: &[u8]) -> Result<Vec<u8>, ReceiptError> {
    match oid {
        OID_SHA256 => Ok(Sha256::digest(data).to_vec()),
        OID_SHA1 => Ok(sha1::Sha1::digest(data).to_vec()),
        other => Err(ReceiptError::Malformed(format!(
            "unsupported digest algorithm {other}"
        ))),
    }
}

/// PKCS#1 v1.5 verification.
///
/// The hash is not always named by the signature algorithm. Apple signs
/// receipts with the bare `rsaEncryption` OID, which names no digest at all, so
/// CMS takes it from the signerInfo's `digestAlgorithm` instead. Assuming
/// SHA-1 for that OID rejects every real receipt.
fn verify_rsa(
    spki_der: &[u8],
    signature_oid: &str,
    digest_oid: &str,
    message: &[u8],
    signature: &[u8],
) -> Result<(), ()> {
    use rsa::pkcs1v15::{Signature, VerifyingKey};
    use rsa::pkcs8::DecodePublicKey;
    use rsa::signature::Verifier;

    let hash = match signature_oid {
        OID_SHA256_WITH_RSA => OID_SHA256,
        OID_SHA1_WITH_RSA => OID_SHA1,
        OID_RSA_ENCRYPTION => digest_oid,
        _ => return Err(()),
    };

    let key = rsa::RsaPublicKey::from_public_key_der(spki_der).map_err(|_| ())?;
    let signature = Signature::try_from(signature).map_err(|_| ())?;

    match hash {
        OID_SHA256 => VerifyingKey::<Sha256>::new(key)
            .verify(message, &signature)
            .map_err(|_| ()),
        OID_SHA1 => VerifyingKey::<sha1::Sha1>::new(key)
            .verify(message, &signature)
            .map_err(|_| ()),
        _ => Err(()),
    }
}

/// Reads the receipt payload, a `SET OF` attribute triples.
fn parse_payload(
    payload: &[u8],
    allowed_bundle_ids: &[String],
) -> Result<VerifiedReceipt, ReceiptError> {
    // Read the SET's contents directly rather than through `SetOfVec`, which
    // enforces canonical DER ordering that real receipts do not always honour.
    let set = der::asn1::AnyRef::from_der(payload)
        .map_err(|e| ReceiptError::Malformed(format!("payload is not DER: {e}")))?;
    let mut reader = der::SliceReader::new(set.value())
        .map_err(|e| ReceiptError::Malformed(format!("payload is not readable: {e}")))?;

    let mut attributes = Vec::new();
    while !der::Reader::is_finished(&reader) {
        let attribute = ReceiptAttribute::decode(&mut reader).map_err(|e| {
            ReceiptError::Malformed(format!("payload holds a malformed attribute: {e}"))
        })?;
        attributes.push(attribute);
    }

    let mut bundle_id = None;
    let mut app_version = None;
    let mut opaque = Vec::new();
    let mut sha1_hash = Vec::new();

    for attribute in &attributes {
        match attribute.attribute_type {
            ATTR_BUNDLE_ID => bundle_id = Some(utf8_string(attribute.value.as_bytes())?),
            ATTR_APP_VERSION => app_version = Some(utf8_string(attribute.value.as_bytes())?),
            ATTR_OPAQUE_VALUE => opaque = attribute.value.as_bytes().to_vec(),
            ATTR_SHA1_HASH => sha1_hash = attribute.value.as_bytes().to_vec(),
            _ => {}
        }
    }

    let bundle_id =
        bundle_id.ok_or_else(|| ReceiptError::Malformed("receipt names no bundle id".into()))?;
    if !allowed_bundle_ids.contains(&bundle_id) {
        return Err(ReceiptError::BundleMismatch { found: bundle_id });
    }
    if opaque.is_empty() || sha1_hash.is_empty() {
        return Err(ReceiptError::Malformed(
            "receipt carries no opaque value or hash to bind against".into(),
        ));
    }

    Ok(VerifiedReceipt {
        bundle_id,
        app_version: app_version.unwrap_or_default(),
        fingerprint: receipt_fingerprint(&opaque, &sha1_hash),
    })
}

/// Identifies one receipt without keeping it. The opaque value is issued per
/// purchase and per device, so two installs presenting the same fingerprint are
/// the same copy.
fn receipt_fingerprint(opaque: &[u8], sha1_hash: &[u8]) -> Vec<u8> {
    // Length-prefixed rather than concatenated. Both fields are fixed width in
    // a real receipt, but a bare join means ("ab", "cd") and ("abc", "d") hash
    // alike, and a fingerprint that can collide is not an identifier.
    let mut hasher = Sha256::new();
    hasher.update((opaque.len() as u64).to_be_bytes());
    hasher.update(opaque);
    hasher.update((sha1_hash.len() as u64).to_be_bytes());
    hasher.update(sha1_hash);
    hasher.finalize().to_vec()
}

fn utf8_string(value: &[u8]) -> Result<String, ReceiptError> {
    let any = der::asn1::Any::from_der(value)
        .map_err(|e| ReceiptError::Malformed(format!("attribute is not DER: {e}")))?;
    let text: der::asn1::Utf8StringRef = any
        .decode_as()
        .map_err(|e| ReceiptError::Malformed(format!("attribute is not a UTF8String: {e}")))?;
    Ok(text.as_str().to_string())
}

#[derive(Debug, Clone, der::Sequence)]
struct ReceiptAttribute {
    attribute_type: u32,
    #[allow(dead_code)]
    version: u32,
    /// `Vec<u8>` would decode as SEQUENCE OF here; the attribute value is an
    /// OCTET STRING whose contents are themselves DER for the typed fields.
    value: der::asn1::OctetString,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy_bundles() -> Vec<String> {
        vec!["com.msdrigg.roam".to_string()]
    }

    #[test]
    fn the_embedded_apple_root_is_the_expected_certificate() {
        let root = Certificate::from_der(APPLE_ROOT_CA_DER).expect("root parses");
        let subject = root.tbs_certificate.subject.to_string();
        assert!(
            subject.contains("Apple Root CA"),
            "unexpected receipt root: {subject}"
        );
    }

    /// The receipt root is not the App Attest root. Confusing the two would
    /// accept a chain signed by the wrong Apple CA.
    #[test]
    fn the_receipt_root_differs_from_the_app_attest_root() {
        assert_ne!(
            APPLE_ROOT_CA_DER,
            super::super::APPLE_ROOT_CA_DER,
            "receipts chain to the general Apple root, attestations to the App Attest root"
        );
    }

    #[test]
    fn garbage_is_not_mistaken_for_a_receipt() {
        let err = verify_receipt(b"not a receipt at all", &policy_bundles(), Utc::now())
            .expect_err("rejected");
        assert!(matches!(err, ReceiptError::Malformed(_)));
    }

    #[test]
    fn an_empty_receipt_is_rejected() {
        let err = verify_receipt(&[], &policy_bundles(), Utc::now()).expect_err("rejected");
        assert!(matches!(err, ReceiptError::Malformed(_)));
    }

    /// A bare certificate is valid DER and valid ASN.1, so it exercises the
    /// path where the outer parse succeeds and the CMS shape does not.
    #[test]
    fn a_certificate_is_not_a_receipt() {
        let err =
            verify_receipt(APPLE_ROOT_CA_DER, &policy_bundles(), Utc::now()).expect_err("rejected");
        assert!(matches!(err, ReceiptError::Malformed(_)));
    }

    #[test]
    fn a_fingerprint_identifies_one_receipt() {
        let a = receipt_fingerprint(b"opaque-a", b"hash-a");
        assert_eq!(a.len(), 32);
        assert_eq!(a, receipt_fingerprint(b"opaque-a", b"hash-a"));
        assert_ne!(a, receipt_fingerprint(b"opaque-b", b"hash-a"));
        assert_ne!(a, receipt_fingerprint(b"opaque-a", b"hash-b"));
    }

    /// The opaque value and hash are concatenated, so a naive join would let
    /// two different receipts collide.
    #[test]
    fn the_fingerprint_does_not_collide_across_a_shifted_boundary() {
        assert_ne!(
            receipt_fingerprint(b"ab", b"cd"),
            receipt_fingerprint(b"abc", b"d")
        );
    }

    #[test]
    fn an_unknown_digest_algorithm_is_refused() {
        let err = digest("1.2.3.4", b"data").expect_err("unsupported");
        assert!(matches!(err, ReceiptError::Malformed(_)));
    }

    #[test]
    fn the_supported_digests_produce_their_own_lengths() {
        assert_eq!(digest(OID_SHA256, b"data").unwrap().len(), 32);
        assert_eq!(digest(OID_SHA1, b"data").unwrap().len(), 20);
    }

    /// Exercises the whole verifier against a genuine Apple-signed receipt.
    ///
    /// Any Mac App Store app on the machine carries one, so the CMS parse, the
    /// chain walk to the pinned Apple root, the RSA signature check and the
    /// payload decode all run on real Apple data. The bundle id is not Roam's,
    /// so a correct verifier gets all the way to the policy check and stops
    /// there: reaching `BundleMismatch` means every earlier step passed.
    ///
    /// Skipped when the machine has no App Store apps, so CI stays green.
    #[test]
    fn a_real_apple_receipt_verifies_up_to_the_bundle_check() {
        let Some(receipt) = std::fs::read_dir("/Applications")
            .ok()
            .into_iter()
            .flatten()
            .flatten()
            .map(|entry| entry.path().join("Contents/_MASReceipt/receipt"))
            .find(|path| path.exists())
            .and_then(|path| std::fs::read(path).ok())
        else {
            eprintln!("no Mac App Store receipt on this machine; skipping");
            return;
        };

        match verify_receipt(&receipt, &policy_bundles(), Utc::now()) {
            Err(ReceiptError::BundleMismatch { found }) => {
                assert!(!found.is_empty(), "a real receipt names its bundle");
            }
            Err(other) => panic!("a genuine Apple receipt failed verification: {other}"),
            Ok(_) => panic!("a receipt for another app must not satisfy Roam's policy"),
        }
    }

    #[test]
    fn an_unknown_signature_algorithm_never_verifies() {
        assert!(verify_rsa(&[], "1.2.3.4", OID_SHA256, b"message", b"signature").is_err());
    }
}
