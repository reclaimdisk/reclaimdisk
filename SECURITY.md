# Security policy

## Supported versions

ReclaimDisk has no release yet. Security fixes land on `main`. Once releases start, the latest release gets them.

## Reporting a vulnerability

Please don't open a public issue. Report it privately on GitHub: open the [Security tab](https://github.com/reclaimdisk/reclaimdisk/security) and click **Report a vulnerability**. Only the maintainers can see the report.

Include what's needed to reproduce it: your macOS version, the ReclaimDisk commit or version (`reclaimdisk --version`), the steps, and what happened.

Examples of what counts:

- ReclaimDisk reads, changes or deletes something it shouldn't, or follows a link or mount point it should skip.
- A crafted file or folder name makes it crash, hang, or show something misleading.
- It leaks information about your Mac to another app or user.

Today ReclaimDisk only reads the disk: it deletes nothing, makes no network connections and sends no telemetry. Cleaning will come in a later version, and reports about it are just as welcome then.

## What happens next

You'll get a reply in the private report. The maintainers confirm whether it's a vulnerability, work on a fix with you in a private fork if needed, and publish a security advisory once a fix is out. You're credited in the advisory unless you'd rather not be named.
