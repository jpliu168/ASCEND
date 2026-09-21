---
name: paper-fetch
description: Get the full-text PDF of any OPEN-ACCESS paper or preprint onto the cluster from a DOI or article URL (Nature, Science, arXiv, ESS Open Archive, or any journal) — the usual first step of an hpcrepro reproduction ("reproduce this paper: <link>"). Wraps the fetch-paper tool, which tries publisher-direct PDF patterns, then the OpenAlex/Unpaywall/Crossref OA indexes, then Europe PMC repository copies, then an arXiv preprint search by title, verifies every download is a real PDF, and reports JSON. Also covers what to do when a paper is paywalled or a site bot-blocks the cluster and the PDF must come in by hand. This tool fetches open-access copies only — it never bypasses a paywall.
---

# Fetching a paper's PDF

`hpcrepro` wants a local PDF (or repo). When the user gives a DOI or an
article URL instead, use `fetch-paper`:

```bash
fetch-paper 10.22541/essoar.15007973/v1 --out /work/$USER/agent-projects/<name>/paper
fetch-paper https://essopenarchive.org/doi/full/10.22541/essoar.15007973/v1 --out ...
fetch-paper <doi-or-url> --dry-run    # list candidate URLs without downloading
```

JSON out: `ok`, `pdf` (absolute path), `source` (which route worked),
`tried[]` (every URL with its error), `errors[]` — plus, on success, a
`verification` block and a one-line `message`. Verification is an
independent post-download re-read of the file from disk: magic bytes
`%PDF`, size > 1 KB, full sha256, byte count, and created/modified
timestamps. `ok` is true **only if this second check passes** — a download
that saved but fails re-verification flips `ok` back to false. So: trust
`ok`, quote `message` to the user, and record `sha256` in the project
notes for provenance. Never treat a saved HTML error page as the paper —
the tool refuses to twice (at download and at verification).

## How it resolves

1. **Direct patterns first** (no API round-trip):
   - ESS Open Archive / ESSOAr DOIs (`10.22541/essoar.*`):
     `https://essopenarchive.org/doi/pdf/<doi>/<vN>` — the `/doi/full/` page
     Cloudflare-403s non-browser clients, but the `/doi/pdf/` endpoint with a
     browser User-Agent usually serves the PDF. Version defaults to `v1`.
   - arXiv: accepts the DOI form (`10.48550/arxiv.*`), an
     `arxiv.org/abs/...` or `/pdf/...` URL, or a bare ID like `2606.00038` —
     all resolve to `https://arxiv.org/pdf/<id>`. arXiv does not bot-block,
     so this route should always work, cluster included.
   - Science/AAAS DOIs (`10.1126/*`): `https://www.science.org/doi/pdf/<doi>`
     — Atypon-hosted like essoar, so expect a possible 403 from the cluster
     even for CC-BY open-access papers; the fallbacks below then take over.
   - Nature / Springer Nature DOIs (`10.1038/*`) and `nature.com/articles/...`
     URLs: `https://www.nature.com/articles/<id>.pdf`. This works for
     open-access articles (all of Nature Communications and Scientific
     Reports, plus OA articles in Nature itself, e.g. AlphaFold
     `10.1038/s41586-021-03819-2`). A paywalled article returns HTML at
     that URL — the `%PDF` check refuses it cleanly and the fallbacks run.
2. **OpenAlex** (`api.openalex.org`, keyless) → `best_oa_location.pdf_url`.
3. **Unpaywall** (`api.unpaywall.org`, needs an email; set
   `FETCH_PAPER_EMAIL`, defaults to the maintainer's) → `url_for_pdf`.
4. **Crossref** → `link[]` entries typed `application/pdf`.

These APIs also find the *published* version when the input is a preprint
DOI (and vice versa) — check `source` in the output so the reproduction
records which version it actually read.

After the whole PDF chain, two **full-text fallbacks** (only when no PDF
was obtainable — the output's `content_kind` and `message` say what was
actually saved: `pdf`, `xml_fulltext`, or `html_fulltext`):
- **Europe PMC full-text XML** — for papers in the PMC OA subset, the
  complete structured text as `.xml`. Reliably full text when it exists.
- **Full-text HTML** — publisher landing pages (nature.com article page,
  science.org `/doi/full/`, essoar `/doi/full/`, then the generic DOI
  redirect), saved as `.html` **only if it passes a full-text assessment**:
  ≥20k chars of visible text, ≥3 section markers (Methods/Results/
  Discussion/References/...), and no paywall signals on a shortish page.
  An abstract-only or paywall-stub page is never saved — the `tried[]`
  entry records the assessment and says why it was refused. Strong paywall
  wording ("Access options", "Buy or subscribe", "Access through your
  institution", ...) rejects at any length; weak wording that also appears
  in sidebars of open pages ("Get access") only rejects short pages.
  Real-world calibration (2026-08-30): Nature's paywalled
  `s41586-026-10953-2` abstract page measures 12,228 visible chars and
  name-drops references/methods/results in its navigation — the length
  threshold plus signals caught it; length alone is not enough for pages
  in the 20–40k range. This guard
  exists because feeding an abstract to `hpcrepro` as "the paper" poisons
  the whole claims extraction.
When the saved file is HTML/XML rather than PDF, say so to the user and
record `content_kind` in the project notes.

5. **Europe PMC** (`ebi.ac.uk/europepmc` REST, keyless) — repository
   copies and author manuscripts. Often the only automated route for
   Nature/Science biomedical papers and anything NIH/ERC-funded whose
   journal page bot-blocks: the accepted manuscript is legally deposited
   in PMC even when the journal PDF is closed. `source` names the PMCID —
   note in the project that it may be the author manuscript, not the
   typeset version.
6. **arXiv title search, last resort** — when every URL route fails, the
   tool looks up the paper's title (Crossref, then OpenAlex) and searches
   the arXiv API for a preprint with a matching title (handles renames like
   "GraphCast: <journal title>"). A hit downloads the **preprint, not the
   version of record** — the JSON carries a `note` saying so. Record the
   arXiv version in the claims ledger and treat published-vs-preprint
   differences as a real risk when extracting quantitative claims.
   Real example: `10.1126/science.adi2336` (GraphCast, Science 2023) is
   CC-BY open access, yet neither OpenAlex nor Unpaywall exposes a PDF URL
   for it — the title search finds arXiv:2212.12794 instead.

## Manual handoff protocol (when the harness cannot fetch anything)

A failed run now ends with a structured `user_action` block: the landing
URL to open in a browser, the exact `scp` command to copy the download to
the cluster, and the exact `fetch-paper ... --register` command to run
afterwards. The protocol:

1. **Relay `user_action` to the user verbatim** — do not paraphrase away
   the exact paths, and do not proceed with abstract-only text while
   waiting. This is a stop-and-ask gate, same in spirit as the tier-3
   approval gate.
2. When the user says the file is on the cluster, run the `step_3`
   register command. `--register` accepts a PDF or full-text HTML, copies
   it to the canonical name, and pushes it through the **same
   verification** as an automated fetch (magic bytes, size floor, sha256,
   timestamps). Garbage or a wrong file is refused, not registered.
3. The output's `source` records "MANUAL download registered by user"
   with the original path, and the message is labeled
   `[MANUALLY DOWNLOADED BY USER, registered + verified]`. Carry that
   provenance into the project notes and claims ledger — a reproduction
   must show where its text came from, and "the user's institutional
   access" is a legitimate, recordable source.

Worked example (WeatherNext Cyclones, paywalled Nature — user has NCSU
library access):

```bash
# user, on their own machine:
#   download from https://doi.org/10.1038/s41586-026-10953-2 in a browser
scp ~/Downloads/s41586-026-10953-2.pdf <user>@login.ncshare.org:/work/<user>/tmp/
# agent, on the cluster:
fetch-paper 10.1038/s41586-026-10953-2 \
  --register /work/<user>/tmp/s41586-026-10953-2.pdf \
  --out /work/<user>/agent-projects/<name>/paper
```

## Browser fallback (`paper-grab`) — Mac, logged-in, one paper, human-in-loop

When even the render step cannot get the full text (paywall needing an
institutional login, a Download button behind a cookie/Duo gate), the Mac-side
`paper-grab` drives a REAL Chrome via Playwright to finish the job:

- Uses a **persistent profile** (`~/.ascend/paper-grab-profile`) you sign into
  ONCE: `paper-grab --login` → log into NCSU Libraries → close the window. The
  session persists for later runs.
- `paper-grab <DOI>` opens the paper **headful** (visible window), clears the
  cookie banner, waits for you to complete any Duo/login prompt, then obtains
  the PDF by fetching the publisher's real PDF URL (`pdfft` / `citation_pdf_url`)
  **with your session cookies** — falling back to clicking Download/View-PDF and
  capturing the download, and finally to "you click, I capture." It verifies
  `%PDF`, rsyncs to the cluster (`--to`/`--dir`), and runs `fetch-paper
  --register` there (MANUAL provenance).
- **Guardrails, non-negotiable:** headful and ONE paper per call (a human is in
  the loop for auth); a daily cap; personal-research use of that paper only.
  NEVER script it over a bibliography, never point it at bulk lists — that is
  the systematic-download the licence forbids and the campus IP would pay for.
- Requires `pip install playwright && playwright install chromium` on the Mac.
  Runs on the **Mac**, not the campus node (there, automation on the campus IP
  is a subscription scraper — use the institutional API / manual instead).

**Publisher automation blocks are a hard stop, not a challenge (verified 2026-09-12).**
Elsevier/ScienceDirect serves automated browsers a block page ("There was a
problem providing the content", a reference number, `CPE00001`) -- it actively
refuses automation. `paper-grab` DETECTS this and stops with guidance; it does
NOT try to evade (no stealth user-agents, no fingerprint spoofing, no
anti-detection flags -- those were removed). When a publisher blocks the
automated browser, the ONLY acceptable paths are the sanctioned API (Elsevier
Article Retrieval, on the entitled campus node) or a genuinely hand-driven
download (you open and click in your own browser), then `paper-drop --file` /
`fetch-paper --register` for the sync+verify half. `paper-grab` is for
publishers that permit logged-in session access; it is not a way past a block.

Escalation order the agent should follow: fetch-paper HTTP routes → (off-campus)
render → still stuck & paywalled on the Mac → `paper-grab`. On the VCL node the
order is: fetch-paper → Elsevier API (if entitled) → Firefox-in-RDP + `--register`.

## Local render fallback — off-campus, anonymous, open-access only

Some publishers (ScienceDirect above all) serve scripts a JavaScript shell:
`200 OK`, ~11 visible characters, no `citation_pdf_url`. Verified 2026-09-12:
a nine-day-old **open-access** Marine Geology paper looked "paywalled" to every
HTTP route only because the OA indexes had not catalogued it yet, while a
rendered page showed the full text with CC-BY markers. "No OA copy found in the
APIs" therefore does NOT mean paywalled for very new papers.

So `fetch-paper` has a last-resort **render** step: if local Chrome exists, it
renders the landing page ONCE with headless Chrome in a throwaway, cookie-less
profile and keeps the result only if it passes the full-text assessment
(saved as `.html` plus an extracted `.txt`; `content_kind: html_fulltext`,
`rendered_with`, and any `license_markers` recorded). The guardrails are the
point:

- **Off-campus only.** An anonymous render from a home/Mac IP can only see what
  any visitor sees -- open-access content. It structurally cannot reach
  subscription material. On a campus-IP host the step is disabled (there the
  campus IP would make headless Chrome a subscription scraper -- use the
  institutional route or a manual download).
- **Anonymous.** Fresh temp profile every time: no library login, no cookies,
  no saved sessions. Never point it at a logged-in profile.
- **One render per paper**, no link-following, no retry loop. If the rendered
  page is still abstract-only it is NOT saved and the manual handoff applies.
- `--no-render` disables it. Check the licence markers before redistributing.

This is what the ASCEND-NCSHARE agent used to do by hand with Chrome; now it is a
deterministic, verified step with the same rules every time.

## Institutional (campus-network) access — licensed, not bypassed

On an **NC State campus-IP host** — an HPC-VCL node like `vclhpc10` — publishers
grant IP-authenticated *subscription* access, the same "Full text access / View
PDF" a browser shows on campus. `fetch-paper` auto-detects this (hostname or
152.1/152.7/152.14 address; `--institutional` / `--no-institutional` or
`FETCH_PAPER_INSTITUTIONAL=1|0` override) and adds ONE more resolver, placed
after the free open-access lookups and before the preprint fallbacks: resolve
the DOI to the publisher landing page and download the `citation_pdf_url` it
advertises — the version of record. Result JSON reports `institutional_mode`
and, on success, `institutional_access: true` plus a `license_note`.

This is NOT a paywall bypass: it uses access NC State pays for and the user is
entitled to. The risk is **institutional**, not legal-for-the-user: publisher
licenses forbid systematic/automated downloading, and their response to a
scripted pattern is to cut off the offending IP range — i.e. the whole campus.
So the tool enforces human pace in code, and you must respect it in behaviour:

- **One paper per call, only the paper the user asked for.** Never loop over a
  bibliography, a search result, or a reading list to fetch many. If a task
  seems to need many papers, STOP and tell the user; bulk needs go through the
  library's TDM contact / the publisher's TDM API, not this tool.
- **Rate caps are enforced** (20 s minimum gap, 10/hour, 30/day, counting
  attempts). When the cap is hit the tool refuses and says so — do not work
  around it, do not retry in a loop, do not spawn parallel fetches.
- **No crawling and no bot evasion.** One landing-page request, then the PDF
  URL it names. If the publisher returns 403 or a JS/bot challenge (Elsevier
  does this even on campus), fall back to the manual handoff — never reach for
  a headless browser, cookies, or UA tricks to get past it.
- **Personal research use of that paper.** Do not redistribute the PDF, build
  a corpus of subscription papers, or feed them into TDM/training pipelines
  (publishers reserve those rights explicitly).
- **Elsevier / ScienceDirect (`10.1016/*`) is the special case.** Its landing page
  is a JavaScript shell to any script (verified 2026-09-12 on vclhpc10: 200 OK,
  11 visible characters, no `citation_pdf_url`) -- so the generic route cannot
  work there, and that is NOT a block to defeat. The sanctioned route is
  Elsevier's official **Article Retrieval API**: set `ELSEVIER_API_KEY` (free key
  from dev.elsevier.com) and `fetch-paper` calls
  `api.elsevier.com/content/article/doi/<DOI>` for the PDF instead of touching
  ScienceDirect at all. TWO things must be true (verified 2026-09-12): the
  request comes from an entitled campus IP, AND the key has **"ScienceDirect
  Full-Text Entitlement" enabled by Elsevier API Support** -- it is access-
  controlled and OFF by default; a fresh key returns 403 `AUTHENTICATION_ERROR:
  Requestor configuration settings insufficient` on full text while the
  abstract API works. Request it via Elsevier's Research Products API support
  (give: API key, "North Carolina State University", the single-article
  research use case, API = ScienceDirect Article Retrieval, default quota).
  Looping in NCSU Libraries' e-resources/TDM contact helps, as licence holder.
  Elsevier applies its own rate limits; ours still apply on top. The key is
  redacted in all recorded URLs.
  Without a key, an Elsevier paper on the VCL node is a 30-second manual step:
  open it in the node's own Firefox and save straight into the target path.
- On a campus node the manual handoff now says exactly that -- download IN PLACE
  with the node's browser, then `--register`; no scp needed.
- Off campus (Mac, NCShare), the manual-handoff `user_action` now includes an
  `alternative`: run the same command on the VCL node first.

Being the reference agent user who never triggers a publisher complaint is
worth more than any single paper. When in doubt, hand off to the human.

## Paywalled papers — the honest boundary

This tool fetches **open-access copies only**. When a paper is genuinely
closed (OpenAlex `oa_status: closed`, no PMC copy, no preprint — e.g. the
WeatherNext Cyclones Nature paper, `10.1038/s41586-026-10953-2`), do not
hunt for mirrors, do not try Sci-Hub-style sources, and do not hammer the
publisher. Tell the user it is paywalled and offer the real options: their
institution's library access in a browser, the publisher's SharedIt/rdcu.be
view links, or emailing an author. Then take the manual-upload path below.

## When everything 403s

Some publishers bot-block all non-residential IPs. Do not retry in a loop
and do not try to defeat the block. Follow the **manual handoff protocol**
above — the failure output's `user_action` block already contains the
exact instructions to relay.

## Provenance

- Route validation, NCShare login-01, 2026-08-30 (three-way test):
  - `10.1038/s41586-021-03819-2` (AlphaFold, OA Nature) → **nature.com
    direct .pdf**, 3.48 MB, verified. The Nature OA route works from the
    cluster — nature.com does not bot-block.
  - `10.1126/science.adi2336` (GraphCast, CC-BY Science) → science.org
    403 as predicted, OA indexes empty, **arXiv title search delivered
    2212.12794v2** (38.13 MB) with the version-of-record caveat. Full
    fallback chain verified end to end.
  - `10.1038/s41586-026-10953-2` (WeatherNext Cyclones, paywalled Nature)
    → correct refusal: nature.com and Crossref both served HTML, `%PDF`
    check rejected both, no OA copy exists anywhere. The tool now
    distinguishes this case ("paywalled, HTML where PDF should be") from
    a Cloudflare 403 in its final message.
- Status: **verified on NCShare, 2026-08-30** — end-to-end success from
  login-01 on `arxiv.org/abs/2606.00038` (651,793-byte PDF via the arXiv
  direct route; the tool stops at the first verified PDF and only consults
  the APIs when no direct pattern delivers). Expected quirk: arXiv DOIs are
  registered with DataCite, so Crossref/Unpaywall 404 on them — not an
  error worth investigating.
- Earlier same-day cluster test against the glacier-MBM preprint (`10.22541/essoar.15007973/v1`), run from login-01:
  - The essopenarchive direct `/doi/pdf/` pattern returns **HTTP 403 from
    the cluster** — Cloudflare blocks NCShare's IP range, not just cloud
    datacenters. A real browser on a residential/campus desktop loads the
    same URL fine. Do not expect the direct route to ever work from the
    cluster for this publisher.
  - OpenAlex, Unpaywall and Crossref all returned **404 for this DOI three
    days after posting** — brand-new preprints are not yet indexed. This is
    a lag, not a block: retry later, or fall back to manual download now.
  - The API fallback chain is therefore still unverified end-to-end on the
    cluster (no candidate URL was ever reachable); first success should be
    recorded here.
- Keep new publisher patterns coming: when a fetch fails and you find the
  working URL by hand, add the pattern to `fetch-paper`'s `candidates()`
  and note it here.
