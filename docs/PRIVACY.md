# Privacy

Screenlogger is designed around a Library owned by the app on this Mac.

## What is stored

Depending on enabled features, a captured moment can include:

- a screenshot;
- recognized foreground and background text;
- application identity and window title;
- website domain and address when Accessibility provides them;
- a bounded accessibility snapshot for structured context;
- capture time, display metadata, and search indexes.

The default Library is:

```text
~/Library/Application Support/dev.screenlog/
```

The app is the sole database owner. The CLI and assistant integrations use a
bounded local connection while Screenlogger is running.

## Permissions

Screen Recording and Accessibility are both required for capture. Without
Accessibility, Screenlogger cannot reliably identify browser websites or apply
all context-dependent exclusions. Permission state checks use macOS preflight
APIs and do not capture content.

Screenlogger asks for Automation access only when the user chooses to launch an
assistant in Terminal.

## Exclusions

Applications and websites can be excluded in Settings. Screenlogger also ships
small project-maintained defaults for common password managers and financial
services. These lists are convenience safeguards, not comprehensive guarantees.
Add services specific to your work before handling sensitive information.

Private browsing protection depends on Accessibility context. If Screenlogger
cannot determine a website while strict protection is enabled, capture pauses.

## Network access

Capture, text recognition, indexing, search, and Library maintenance do not
require a network connection.

Website-icon fetching is off by default. When enabled, Screenlogger sends only a
domain name to DuckDuckGo's public icon endpoint. It does not send screenshots,
recognized text, full page addresses, or Library identifiers for this feature.
Keep Screenlogger Offline disables optional network requests.

## Assistant integrations

Screenlogger prepares a bounded search request and asks the selected assistant to
use the local `screenlog` command. The assistant may send the request and any
retrieved content to its configured provider. That transmission is controlled by
the assistant, not Screenlogger. Review the assistant's account and privacy
settings before connecting it.

External command access is read-only by default. Capture control and Library
maintenance require a separate opt-in in Integrations.
