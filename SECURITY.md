# Security Policy

Zoe drives Claude Code, which can run commands, edit files and send messages through connectors. So safety bugs matter. That includes:
- a way around the approval gate (a tool that runs a write, send or command without approval),
- prompt injection from screen text, the clipboard, dropped files or connector results that leads to an unapproved action or a network call,
- another process being able to talk to the core or fake an approval,
- audio or transcripts being stored or leaving the Mac.

## Reporting a vulnerability

Please **don't open a public issue**.
- Use GitHub's private reporting: **Security → Report a vulnerability** on this repository.
- Include:
  - macOS version and Zoe version (or commit),
  - steps to reproduce,
  - what you expected and what happened.
- You'll get an acknowledgement within a few days. Fixes are released as soon as practical, and reporters are credited unless they'd rather not be.

## Supported versions

Only the latest release gets security fixes.
