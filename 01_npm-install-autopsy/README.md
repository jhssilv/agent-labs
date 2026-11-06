# npm install, at the system-call level

The reproducible setup behind the post
[*What happens when Claude Code runs npm install*](https://josehenrique.dev/posts/npm-install-syscall-autopsy/).

It runs one clean `npm install` under `strace` and prints what the machine
actually did: how many processes started, how many files were opened, and how
many real TCP connections were made.

## Run it in a container (easiest)

```sh
podman build -t npm-autopsy -f Containerfile .

podman run --rm --cap-add=SYS_PTRACE --security-opt seccomp=unconfined npm-autopsy
```

Use `docker` in place of `podman` if you prefer. Both flags are required:
`strace` traces with `ptrace`, and a container's default seccomp profile blocks
`ptrace`, so `SYS_PTRACE` (the capability) plus `seccomp=unconfined` (to let the
`ptrace` syscall through) are what make tracing work inside the container.

## Run it directly

Needs `strace`, `node`, and `npm`:

```sh
./run-autopsy.sh
```

## What to expect

A harmless install of `express` and `core-js`. On the machine in the post
(Fedora 43, Node 22, npm 10):

- **2 or 3 processes**: `npm` (which is Node, with ~17 threads) and the
  `core-js` postinstall, `node -e "..."` -- a package running its own code at
  install time. On the host it is 2; in this Debian container it is 3, because
  its `/bin/sh` (dash) forks a separate `node` for the postinstall where a
  bash-based `/bin/sh` exec's it in place. Same postinstall either way.
- **~6,000 files** opened, almost all of them the `node_modules` tree.
- **about a dozen TCP connections** on port 443, to one or two IP addresses.

A naive `grep connect` overcounts badly: most `connect()` calls in the trace are
UDP probes `getaddrinfo` makes to sort candidate addresses (RFC 6724), which
send no packets. The script filters to TCP on 443, which is the real traffic.

Two caveats worth stating plainly:

- **IP is not host.** The kernel sees IP addresses, not names. That they belong
  to `registry.npmjs.org` comes from DNS, not from `connect()`; a request to
  another domain behind the same CDN would look identical here.
- **The CA finding is build-specific.** Node's official build bundles its own
  certificates, so it never reads the system CA store. A distro build with
  `--use-openssl-ca` would read `/etc/ssl` or `/etc/pki`.

Files and processes are stable between runs; the connection count moves a little
because npm opens its sockets in parallel.

## Notes

- A container shares the host's kernel, so the kernel version is your machine's.
  For a kernel of its own, run it in a VM.
- `npm install` runs third-party code (lifecycle scripts). Here it is harmless
  on purpose -- that is the point of the post. `npm install --ignore-scripts`
  skips them, and pnpm 10 blocks them by default.
- To pin the image for good, replace the `FROM` line with a digest
  (`FROM node:22-bookworm-slim@sha256:...`).
