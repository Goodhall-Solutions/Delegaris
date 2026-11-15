# Security

Delegaris holds roles that can start and stop machines in your AWS accounts, so we take security reports seriously.

## Reporting a problem

Please **do not** open a public issue for a security problem. Email **security@goodhallsolutions.co.uk** with:

- what you found and how to reproduce it,
- the Delegaris version (shown at `/healthz`, or by `delegaris version` on Linux),
- how it is installed (Docker or the Linux package) and anything unusual about the set-up.

We will acknowledge your report within three working days, keep you told how we are getting on, and credit you in the release notes if you would like.

## Supported versions

Fixes go into the latest release. Upgrade to it: see [Upgrading](https://docs.delegaris.co.uk/operations/upgrading).

## How Delegaris is built to be safe

See [Security](https://docs.delegaris.co.uk/operations/security) in the documentation: what it stores and how, what is encrypted, the activity log, and the least-privilege IAM it needs.
