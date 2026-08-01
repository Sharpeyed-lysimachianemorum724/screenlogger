# Install Screenlogger

This archive accompanies the Screenlogger DMG and supports macOS 14 or later.
The prerelease has a complete ad-hoc signature, but it is not Developer ID
signed or notarized.

1. Open the DMG.
2. Drag Screenlogger to Applications.
3. Open the installed copy. If macOS blocks it, Control-click Screenlogger,
   choose Open, and confirm Open.
4. Complete Setup. Screen Recording and Accessibility are both required.
5. Choose Start Capture when ready.

Replacing or removing the app does not delete the Library.

## Optional Terminal command

Install `screenlog` from Screenlogger Settings under Integrations. The technical
ZIP also includes a `CLI` directory. Keep its executable, framework, and skill
directory together because the command uses relative runtime paths.

## Verify the download

GitHub Releases includes `.sha256` files and a JSON manifest beside each DMG and
ZIP. Verify the checksum before installing. Automatic replacement remains
disabled until Developer ID signing and notarization are available.
