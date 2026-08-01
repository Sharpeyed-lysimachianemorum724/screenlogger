# Command Line Interface

The `screenlog` command is a client of the running Screenlogger app. It does not
open the SQLite database directly.

Install it from Settings under Integrations, then verify the connection:

```sh
screenlog --version
screenlog doctor
screenlog status
```

## Search and inspect

```sh
screenlog search "invoice overdue" --limit 20
screenlog query frame --id 42 --show-ocr
screenlog image --id 42 --out /tmp/frame.heic
screenlog list applications
screenlog list domains
```

Library search accepts the same `app:`, `site:`, `date:`, `since:`, and
`before:` refinements used by the app.

## Activity summaries

```sh
screenlog usage time
screenlog usage top-applications
screenlog usage top-domains
screenlog usage sessions
```

## Capture and maintenance

```sh
screenlog record start
screenlog record stop
screenlog record once
screenlog compact
screenlog retention
```

These commands require Allow capture control and maintenance in Screenlogger
Settings. Search and status remain read-only.

## Automation contracts

Use `--json` where available. Status, diagnostics, and assistant-readiness JSON
use versioned schemas and stable issue codes. Private Library and socket paths are
not included.

Run `screenlog --help` and `screenlog <command> --help` for the current command
reference.
