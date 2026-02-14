# VM Tool

Menu-driven VM bootstrap runner.

## Run

```bash
cd vm-tool
sudo ./main.sh
```

Requires `whiptail` (preferred) or `dialog`.

## Add a new component

1. Create an executable script in `components/`, e.g. `30-docker.sh`.
2. Add optional metadata headers in the script:

```bash
# NAME: Install Docker
# DESC: Install Docker engine and CLI
```

3. Optionally register it in `components.json` for explicit menu naming/order.

## Notes

- If `components.json` exists and `jq` is installed, menu entries are loaded from JSON.
- Otherwise, executable `components/*.sh` files are auto-discovered.
- Some components require internet access (for example Oh My Zsh install).
