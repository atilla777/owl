# Purpose

Translate findings into a short list of distinct viable options, each with pros / cons.

## When to use

In `research` workflow after `findings`.

## Inputs

- `research_findings` artifact.

## Outputs

- Options notes in conversation context; passed forward to the `recommendation` step.

## Notes

The seeded `research` workflow does not require an artifact for this step. Capture
options in the next-step recommendation artifact.
