# TrustBeat Anchor — qualified EU timestamps for your builds

**Legal proof of *when*.** This action anchors your release artifacts with an
**eIDAS-qualified timestamp** — the only kind that is *presumed valid in court*
across all 27 EU member states (eIDAS Art. 41). One YAML block instead of a
QTSP contract.

- ⚖️ **Court-grade evidence** — qualified timestamps from EU Trusted List
  providers, not a self-run TSA
- 🛡️ **NIS2 / DORA audit evidence** — prove your artifacts, SBOMs and reports
  existed unmodified at a point in time
- 🔒 **Nothing leaves your runner** — the SHA-256 is computed locally; only the
  64-hex digest is transmitted
- 🔍 **Independently verifiable** — Merkle inclusion proof + RFC 3161 token;
  anyone can verify [without trusting TrustBeat](https://trustbeat.eu/en/manual-verify),
  even offline

> **Not a signing tool.** Sigstore/Cosign prove *who* built an artifact — use
> them! TrustBeat proves *when* it existed, with EU legal standing. The two
> compose.

## Quickstart

```yaml
- name: Anchor release artifacts
  uses: TrustBeat/anchor-action@v1
  with:
    api-key: ${{ secrets.TRUSTBEAT_API_KEY }}
    files: |
      dist/*.tar.gz
```

Get an API key in under a minute — free tier, 100 anchors/month, no card:
**[trustbeat.eu/register](https://trustbeat.eu/register)**.

The job summary shows a verify link per file plus a badge snippet:

[![Anchored — qualified EU timestamp](https://api.trustbeat.eu/v1/public/badge/01JQEXAMPLE)](https://trustbeat.eu/verify?id=01JQEXAMPLE)

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `api-key` | ✅ | — | TrustBeat API key (`tb_live_…`), from a repo secret |
| `files` | ✅ | — | Files to anchor — one glob/path per line |
| `description` | — | `<repo>@<ref>` | Label stored with each anchor |
| `client-ref` | — | commit SHA | Your correlation reference |
| `wait` | — | `false` | `true` blocks until the proof is issued (≤ ~10 min). Default submits fast; proofs go live automatically when the batch fires |
| `api-url` | — | `https://api.trustbeat.eu` | API base URL |

## Outputs

| Output | Description |
|---|---|
| `results` | JSON array of `{file, hash, id, verify_url, badge_url}` |
| `ids` | JSON array of tracking IDs |

## How it works

1. `sha256sum` each matched file **on the runner**.
2. `POST /v1/anchor` — the hash joins the next Merkle batch (every 10 minutes,
   at `:00, :10, :20…` — [live schedule](https://api.trustbeat.eu/v1/public/anchor/status)).
3. The batch's Merkle root receives one RFC 3161 **qualified** timestamp from
   an EU Trusted List provider.
4. Your proof = Merkle inclusion path + the qualified token. Fetch it via the
   verify link, the [API](https://api.trustbeat.eu/docs), or any
   [SDK](https://trustbeat.eu/sdks) — and long-term validity is maintained
   automatically by archive re-stamping (30+ years, eIDAS).

## Why qualified timestamps?

An ordinary timestamp (or a transparency-log entry) proves inclusion to anyone
who trusts the operator. A **qualified** timestamp under eIDAS Art. 42 carries a
*legal presumption* of accuracy in every EU court — the burden of proof flips to
whoever disputes it. If your artifacts may ever be evidence (NIS2 incident
reports, DORA audits, IP disputes, regulated releases), qualified is the
difference between "trust us" and "presumed valid".

---

Maintained by [Trustbeat s.r.o.](https://trustbeat.eu) · [API docs](https://api.trustbeat.eu/docs) · [SDKs](https://trustbeat.eu/sdks) · MIT license
