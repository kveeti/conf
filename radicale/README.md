# Radicale image

Build the image for the current Linux system with:

```sh
nix build ./radicale#dockerImage
```

The image runs as UID/GID `1000`, listens on port `5232`, and expects:

- A writable volume mounted at `/var/lib/radicale`.
- An htpasswd file mounted read-only at `/run/secrets/radicale-users`.

The entrypoint initializes Git in the data directory if needed. Radicale's storage hook keeps the birthday calendar in sync and commits collection changes, matching the current NixOS setup.

GitHub Actions builds amd64 and arm64 images for pull requests. Run the workflow manually to publish `veetik/radicale-and-friends`; it uses the `DOCKERHUB_TOKEN` repository secret. Pushes to `main` do not publish images.
