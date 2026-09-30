# Run a NetBird peer on Railway

Stand up a NetBird peer on Railway in a few seconds.
Route into Railway's private network.
Run an exit node.
No `NET_ADMIN`, no TUN device, no problem.

<!-- TODO: add the Deploy on Railway button once the template is published -->

## How it works

Railway containers don't get a TUN device or `NET_ADMIN`, so a stock NetBird client can't create its WireGuard interface.
This recipe builds on NetBird's official `rootless` image, which runs in **netstack mode** (`NB_USE_NETSTACK_MODE=true`): WireGuard and routing run entirely in userspace, with no kernel interface.

On top of the upstream image, this recipe:

- Runs as root, so NetBird can write its state to the Railway volume (Railway mounts volumes as root, and the upstream image's unprivileged user can't write to them).
  No extra capabilities are needed.
- Gives NetBird's `rootless` entrypoint PID 1 so it receives Railway's `SIGTERM` and shuts down cleanly.
- Reshapes NetBird's logs into single-line JSON with `level` and `message` fields that Railway can filter.

## Configuration

### Persist state on a volume

NetBird keeps its WireGuard key and peer identity on a volume.
Without it, every redeploy registers a brand-new peer and leaves the old one behind in your dashboard.

The template points NetBird's state at the volume's mount path for you, so there's nothing to set, even if you change the mount path:

```sh
NB_STATE_DIR="${{RAILWAY_VOLUME_MOUNT_PATH}}"
NB_CONFIG="${{RAILWAY_VOLUME_MOUNT_PATH}}/config.json"
```

If you deploy without the template, attach a volume and set these two variables yourself, or mount the volume at `/var/lib/netbird`, which is the upstream image's default.

### Set your NetBird setup key

Set your NetBird setup key for the variable `NB_SETUP_KEY`.
You can create a new key in the [NetBird dashboard](https://app.netbird.io/setup-keys):

_Setup Keys > Create Setup Key_

A one-off key is enough.
The key is only used for the first login; after that the peer authenticates with the identity stored on the volume.
Don't mark the key **Ephemeral**: ephemeral peers are removed after being offline for a while, which works against the persisted state.

Assign the key an auto-assigned group (for example `railway`) so you can target this peer in access policies and networks.

### Set the peer name

Railway gives each container a random hostname, so set a name that is stable across deploys:

```sh
NB_HOSTNAME="${{RAILWAY_SERVICE_NAME}}-${{RAILWAY_ENVIRONMENT_NAME}}"
```

### Use a self-hosted management server (optional)

The peer connects to NetBird Cloud by default.
To use your own NetBird deployment, point it at your management server:

```sh
NB_MANAGEMENT_URL="https://netbird.example.com"
```

### Set the Docker image version (optional)

You can pin to a specific version of the NetBird `rootless` image by setting the `VERSION` variable.
Keep the `-rootless` suffix; the other NetBird images need a TUN device and `NET_ADMIN`.

```sh
VERSION="0.79.0-rootless"  # defaults to "rootless-latest"
```

### Further customize the peer configuration (optional)

Every `netbird up` flag can be set as an `NB_`-prefixed environment variable (for example `--log-level` becomes `NB_LOG_LEVEL`).
See `netbird up --help` and the [NetBird docs](https://docs.netbird.io/how-to/cli).

## Routing into Railway's private network

This peer can act as a routing peer, giving your NetBird clients access to other services on `railway.internal`.
Unlike Tailscale, routes are configured centrally in the NetBird dashboard, not on the peer, so no extra variables are needed here.

In the [NetBird dashboard](https://app.netbird.io/networks), under _Networks > Add Network_:

1. Add a resource for Railway's private network:
   - `*.railway.internal` as a **domain** resource.
     The routing peer resolves these names with Railway's internal DNS, so clients can reach `my-service.railway.internal` without any nameserver setup.
   - Optionally, `10.128.0.0/9` as a **subnet** resource, to reach services by private IP.
2. Add this peer (or its `railway` group) as the network's **routing peer**.
3. Add an access control policy that allows your users' groups to reach the resources.

Railway's legacy private networking is IPv6-only (`fd12::/16`).
If your environment predates Railway's IPv4 private networking, redeploy into a newer environment or check that your NetBird version supports IPv6 routes before relying on subnet resources; domain resources are the most reliable option.

### Serving as an exit node

To route all of a client's internet traffic through Railway, create a network route for `0.0.0.0/0` with this peer as the routing peer (_Network Routes > Add Route > Exit node_), then select it as the exit node on your client.

## Things to know

- **Connections are usually relayed.**
  Railway doesn't accept inbound UDP, so peers generally can't hole-punch a direct WireGuard connection and fall back to NetBird's relay servers.
  Expect somewhat higher latency than a direct connection.
- **Local DNS is disabled.**
  The `rootless` image sets `NB_DISABLE_DNS=true`, so this container itself doesn't resolve NetBird DNS names.
  This doesn't affect routing for other peers.
- **Other Railway services can't use the tunnel directly.**
  In netstack mode there is no network interface for other services to route through.
  If a service in this project needs to reach your NetBird network, run a NetBird peer in that service.
  NetBird's built-in SOCKS5 proxy listens on loopback only; you can expose it on the private network with `NB_SOCKS5_LISTENER_ADDRESS="::"`, but it has no authentication, so anything on the network can use it.

## Related projects & attribution

- [NetBird client Docker images](https://github.com/netbirdio/netbird/tree/main/client)
- [Railway Tailscale node](https://github.com/jayhale/railway-tailscale), which this recipe is modeled on
