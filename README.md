# OkForward

OkForward is a small macOS menu bar TCP forwarding proxy.

It listens on a selected local interface and bind port, then proxies raw TCP bytes to a target host and target port. For example:

```text
192.168.64.1:2222 -> 127.0.0.1:22
192.168.64.1:18080 -> 127.0.0.1:8080
```

Saved enabled rules start automatically when the app launches.

## Build

```bash
./scripts/build.sh
```

The app bundle is created at:

```text
build/OkForward.app
```

## Run

```bash
./scripts/run.sh
```

Use the `OKF` item in the macOS menu bar to open the rule editor.

## Test

```bash
swift test
```
