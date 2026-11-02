# Security

Please report a security problem privately, through
[GitHub's private reporting](https://github.com/volodya88i/jGlancer-MacOS/security/advisories/new), not in a public
issue. Include the version and the steps to reproduce it.

## The network

- The update check asks only `api.github.com` for the latest release. It installs nothing: it offers to open the release
  page, whose address is built from a fixed repository and a number that must look like `1.2.3`. Release notes are
  shown as plain text.
- A stem model is downloaded only when you press Download, from a fixed address, and is used only if its SHA-256 matches
  the one built into the app.
