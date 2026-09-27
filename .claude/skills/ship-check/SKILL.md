---
name: ship-check
description: Run before handing over any piece of work. Verifies it actually runs, reviews the diff, and states what was deliberately left out.
---

Do these in order. Show real output, not a description of it.

## 1. Prove it runs

Run the test command and the build. Paste the output and the exit code.
If either fails, stop here and fix it. Nothing below matters while the suite is red.

## 2. Review the diff

Run `git diff` and read it as if someone else wrote it. Use the `code-reviewer` subagent
on anything longer than a screen. Report what it found, including nothing if it found nothing.

## 3. The states check

For anything with a user interface, confirm each one exists and is reachable:
loading, empty, error with a retry, and a submit control that disables itself while pending.
Name any that are missing rather than quietly leaving them out.

## 4. Say what you did not do

List what was cut and why it was the right thing to cut. An honest list of exclusions
is worth more than a claim of completeness.

## Output

Four short sections, in that order. No preamble.
