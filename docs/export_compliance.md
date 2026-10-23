# Export compliance

**This is not legal advice. It is a summary of what was found on 23 October
2026 so you know which questions to ask, and it needs verification against
the current regulations before you rely on it.**

WhatsWave implements the Signal Protocol, AES-256-GCM and AES-256-CTR, and
Curve25519. That is cryptography the app carries itself, not cryptography
borrowed from the operating system — which is what puts it inside export
control rules at all.

## 1. Done: the Info.plist declaration

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
```

Without this, every single upload stops on App Store Connect's export
questionnaire. With it, uploads proceed.

**It is a declaration, not a compliance measure.** Setting it true says "yes,
this app contains non-exempt encryption" — it does not discharge anything
below.

### Why not `false`?

The exemptions cover apps whose only encryption is HTTPS, or is provided by
the OS, or is limited to authentication or DRM. WhatsWave does none of those
— it ships its own implementation of a messaging protocol. Declaring `false`
would be a false statement on an export declaration.

## 2. Probably not owed: the BIS annual self-classification report

Historically, mass-market encryption software self-classified as **ECCN
5D992.c** had to be reported to BIS and the NSA every year by 1 February,
covering the prior calendar year, by email to `crypt-supp8@bis.doc.gov` and
`enc@nsa.gov`.

**BIS has since relaxed this.** The reporting obligation was narrowed to
mass-market *components* and their executable software. Stand-alone products
— toolkits and finished products — were dropped from the requirement.

WhatsWave is a stand-alone end-user application, not a component another
developer embeds. On the face of it that puts it in the relieved category.

**Verify this before relying on it.** The relief is recent, the distinction
between "component" and "stand-alone product" is exactly the kind of line
that is clearer in a law firm's summary than in practice, and the penalty for
getting export control wrong is not a fine you shrug off. Check the current
text at
<https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-742/appendix-Supplement%20No.%208%20to%20Part%20742>,
and if there is any doubt, file. Filing when you did not have to costs an
email; not filing when you had to does not.

## 3. Still open: the French declaration

Apple asks, during submission, whether the app is available in France and
whether a French encryption declaration has been filed. France regulates
cryptography separately from the US and the question is asked regardless of
what BIS requires.

Answer it honestly when it appears, and if the answer is "no declaration
filed", be prepared either to file one or to exclude France from the
territories.

## 4. What is NOT required here

- **A CCATS classification.** That is for items needing a formal BIS review,
  not for mass-market software using published, standard algorithms.
- **An export licence.** Mass-market encryption using standard algorithms is
  authorised without one.
- **`ITSEncryptionExportComplianceCode`.** That key only applies once you hold
  an approval code from a CCATS or French filing. Adding it without one would
  be asserting an authorisation you do not have.

## 5. Honest summary

The engineering is done. What remains is a determination — whether the BIS
relief applies to you — and that is a legal question, not a code change.

For a solo developer shipping an encrypted messenger worldwide, an hour with
an export-control lawyer is cheap next to the alternative. The relevant
facts are: ECCN 5D992.c, mass-market, standard published algorithms, no
proprietary cryptography, distributed through the Apple and Google stores.
