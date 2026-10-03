# skills-learned/ — the ASCEND shared skill library

Skills that ASCEND agents drafted during real sessions and a human promoted.
This folder is how one user's solved problem becomes everyone's capability:

```
agent drafts it            human promotes it            everyone gets it
<project>/skills-draft/ -> ascend-skill install <name> -> ascend-skill share <name>
                           (loads in every future          (lands here; commit + push)
                            session on that machine)
                                                          git pull
                                                          ascend-skill install <name>
```

House rules (same as the knowledge base):
- A draft is inert until a human installs it — nothing auto-applies.
- Every SKILL.md carries a `provenance:` line: date, resource, and the
  evidence (job IDs, files) that demonstrated it.
- No usernames, hostnames, or private paths — tokenized like the templates.
- One skill per job; extend an existing skill rather than adding an overlap.

Browse with `ascend-skill list`, inspect with `ascend-skill show <name>`,
remove locally with `ascend-skill retire <name>`.
