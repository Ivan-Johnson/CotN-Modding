# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

## Priority

Separate from the triage roles above: this repo doesn't do versioned releases, so there's no milestone to bucket "must ship by X" work. Instead, a single label marks "work on this before the rest of the backlog":

| Label          | Meaning                                                           |
| -------------- | ----------------------------------------------------------------- |
| `priority:now` | Actively want this worked next; jump the frontier queue           |
| *(unlabeled)*  | Backlog default — fine, just not urgent                           |

`priority:now` composes with the triage labels above and with blocking edges: an issue can be `priority:now` **and** `ready-for-agent` **and** still gated by an open blocker. It only means "prioritize me," not "unblocked" or "ready" — check those separately.

## Topic labels

`agent-explorability` marks anything that makes it easier for AI agents to explore and learn about CotN, such as test helpers or docs. It is a topic, not a triage role, so it composes with every label above.
