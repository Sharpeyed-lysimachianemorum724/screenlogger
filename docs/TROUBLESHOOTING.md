# Troubleshooting

## Screenlogger is missing from a permission list

Install the app in Applications first. In Setup, use Show in Finder and drag the
stationary Screenlogger app tile into the open System Settings list if the Add
button does not discover it. Do not run permission setup from the mounted DMG.

## Permission still appears disabled

Return to Screenlogger and use Refresh. Screen Recording changes can require
quitting and reopening the app. Screenlogger does not repeatedly request a
permission after the first explicit request.

## The CLI cannot connect

Open Screenlogger and run:

```sh
screenlog doctor
screenlog skill status all
```

If the shell cannot find the command, add `~/.local/bin` to the shell path or
reinstall Terminal Access from Settings.

## An assistant opens but does not run the request

Verify the assistant under Integrations and restart it after installing or
upgrading its skill. Terminal assistants use an isolated working directory to
avoid project pickers. `screenlog skill status <target> --json` reports a stable
remediation code without exposing private paths.

## Capture pauses

Open the menu or Capture Settings for the exact reason. Common causes are missing
permission, an exclusion, private browsing, an unknown website under strict
protection, inactivity, or low disk space.

## Diagnostics

Settings under Support and About can export a bounded diagnostics bundle. It
contains structured operational events and configuration summaries, not captured
screenshots or recognized text. Review the bundle before sharing it.
