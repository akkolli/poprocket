# iOS Homelab App Research Report

**Date:** May 25, 2026  
**Scope:** Research whether an iOS app already exists that lets a user receive notifications from custom programs, expose/update homelab device status, and configure iOS widgets that communicate with homelab APIs.

## Executive verdict

I would classify this idea as **“exists in pieces; one close competitor exists; a differentiated homelab-first product gap still exists.”**

You should **not** build a generic “custom API widgets + notifications” app as the core product. **HyperDash** already advertises much of that: configurable native widgets connected to REST APIs/webhooks, automation, custom alerts, Apple Shortcuts, IoT integrations, local/on-device encryption, no account, and a 60-second refresh option in Pro mode.

You **could** still build something valuable if the product is more specifically:

> A local-first, programmable, config-as-code iOS control plane for homelabs, with widgets, actionable notifications, audit logs, typed API cards, Shortcuts/App Intents, and a self-hosted bridge container.

That version is not clearly covered by one existing app.

## Desired capability model

Assumption: the goal is an **App Store-distributable iOS app**, not a jailbreak/private-API tool.

Let the desired system be an iOS app \(A\), optionally paired with a homelab bridge service \(B\). The useful capability vector is:

| Capability | Meaning | Does it already exist? |
|---|---|---|
| \(C_1\) Script-to-phone notifications | A Python/shell/Go program can notify the iPhone. | Yes. ntfy, Pushover, PushBack/Simplepush, Pushcut. |
| \(C_2\) Actionable notifications | Notification buttons trigger callbacks into homelab APIs. | Yes, partially. Pushcut, Simplepush, PushBack, Home Assistant. |
| \(C_3\) Configurable API widgets | Widgets poll/render REST/JSON/webhook data. | Yes. HyperDash, AnyMetrics, API Widgets, Backend Widget, HTTPWidget. |
| \(C_4\) Homelab status dashboards | Proxmox, Unraid, servers, uptime, metrics, etc. | Yes, but verticalized. |
| \(C_5\) Programmatic configuration | YAML/JSON/GitOps-style widget/action definitions. | Not clearly solved. |
| \(C_6\) Local-first/self-hosted semantics | Minimal vendor cloud, secrets in Keychain, local bridge. | Partially solved. |
| \(C_7\) “Freely interact with phone” | Arbitrary phone control. | Not possible in the broad sense on stock iOS. Use Shortcuts, App Intents, notifications, widgets, URL schemes, HomeKit, and allowed background APIs instead. |

## Existing products by category

### 1. Closest direct competitor: HyperDash

**Evidence type:** vendor/App Store listing.

HyperDash is the strongest existing match. It advertises native iOS/iPadOS widgets that connect to REST APIs, webhooks, Make.com, Apple Shortcuts, IoT, local variables, custom alerts, automation, and per-widget API connections. It also advertises local encryption, no cloud account, and no tracking.

**Implication:** the generic version of your idea already exists.

**Likely gaps:** HyperDash appears to be a no-code/API-widget product rather than a full homelab developer platform. I did not find clear evidence of GitOps-style config, typed homelab templates, bidirectional action audit logs, a self-hosted bridge daemon, first-class Proxmox/Docker/Uptime Kuma/Prometheus integrations, or a programmable event bus.

**Source:** [HyperDash on the App Store](https://apps.apple.com/us/app/hyperdash-custom-widget-maker/id6736696637)

### 2. API/widget dashboard apps

**Evidence type:** vendor/App Store listings.

AnyMetrics is a free/open-source app that creates widgets from HTTP endpoints, REST APIs, JSON, web pages, and status checks. Its listing explicitly mentions server uptime, health checks, CI/CD status, JSON parsing, CSS selectors, request headers, timeouts, and compact iOS widgets.

API Widgets, Backend Widget, and HTTPWidget also cover the “display arbitrary API data in iOS widgets” niche. API Widgets advertises connecting any webhook or API endpoint and rendering JSON in customizable iOS widgets.

**Implication:** “widgets configured to call APIs” is not novel by itself.

**Likely gap:** these apps look more like widget/data-display tools than full bidirectional homelab control planes.

**Sources:**

- [AnyMetrics on the App Store](https://apps.apple.com/us/app/anymetrics-api-widgets/id1609900961)
- [API Widgets on the App Store](https://apps.apple.com/us/app/api-widgets/id6756238482)

### 3. Programmable iOS widget/runtime app: Scriptable

**Evidence type:** App Store listing.

Scriptable lets users write JavaScript that integrates with iOS features, files, calendars, reminders, documents, Siri Shortcuts, and Home Screen widgets. Its examples include widgets, notifications, web-service checks, weather-station widgets, and Shortcut integration.

**Implication:** the “write programs that interact with iOS widgets/notifications” angle already exists in a developer-oriented form.

**Likely gap:** Scriptable is a scripting environment, not a homelab-specific API dashboard with persistent remote event ingestion, typed widgets, device templates, observability semantics, and clean bidirectional action routing.

**Source:** [Scriptable on the App Store](https://apps.apple.com/tr/app/scriptable/id1405459188)

### 4. Notification-from-script apps

**Evidence type:** official docs/listings.

ntfy is a simple HTTP pub-sub notification system. Its docs show sending notifications to phones from scripts using HTTP PUT/POST, with support for priorities, attachments, action buttons, tags, and emojis.

Pushover is a mature notification API for phones, watches, scripts, servers, monitoring systems, IoT, and webhooks.

Simplepush and PushBack support interactive/actionable notifications. Simplepush documents action buttons that can return feedback or trigger HTTP GET requests, and PushBack’s listing describes synchronous interactions, callback URLs, buttons, replies, and curl-based setup.

**Implication:** “my homelab script can notify my iPhone” is already solved.

**Likely gap:** these are notification channels, not configurable widget/control surfaces.

**Sources:**

- [ntfy](https://ntfy.sh/)
- [Pushover on the App Store](https://apps.apple.com/us/app/pushover-notifications/id506088175)
- [Simplepush API docs](https://simplepush.io/api)

### 5. Actionable automation: Pushcut and Home Assistant

**Evidence type:** official docs.

Pushcut supports notification actions that can run Shortcuts, send URL/web requests, trigger server actions, or control HomeKit scenes. Its docs explicitly describe HTTP/HTTPS background requests for custom web services and DIY home-server APIs.

Pushcut’s stronger automation server feature can run shortcuts automatically, but it requires a dedicated iOS device and the app must remain in the foreground for the server to process requests.

Home Assistant’s iOS companion app supports actionable notifications where notification buttons send events back to Home Assistant, and it has iOS widgets including scripts, sensors, and beta custom widgets with tap actions.

**Implication:** bidirectional mobile-to-server action flows already exist.

**Likely gap:** Pushcut is automation-centric, Home Assistant is HA-centric, and neither is a general homelab developer cockpit unless you adopt their surrounding ecosystem.

**Sources:**

- [Pushcut notification docs](https://pushcut.io/support/notifications)
- [Pushcut automation server docs](https://pushcut.io/support/automation-server)
- [Home Assistant actionable notification docs](https://companion.home-assistant.io/docs/notifications/actionable-notifications/)

### 6. Homelab-specific apps

**Evidence type:** App Store listings.

There are native homelab/infra apps already. HomeLab Go monitors and manages Proxmox, TrueNAS, and Proxmox Backup Server, including VM/LXC actions, ZFS snapshots, SMB/NFS, backups, widgets, notifications, Keychain storage, self-signed cert support, and Tailscale support.

Unraid Manager monitors and controls Unraid servers, including Docker containers, VMs, system health, notifications, and multiple servers. Server Status monitors CPU, temperature, memory, storage, network, system info, and supports Home Screen widgets.

**Implication:** homelab monitoring/control exists, but mostly as vertical apps.

**Likely gap:** a generic “bring your own API, define your own widgets/actions/events as code” app remains plausible.

**Sources:**

- [HomeLab Go on the App Store](https://apps.apple.com/ca/app/homelab-go/id6746137876)
- [Unraid Manager on the App Store](https://apps.apple.com/us/app/unraid-manager/id6749525537)

## iOS constraints that shape the product

**Evidence type:** engineering rationale, supported by Apple docs.

A stock iOS app cannot be an always-running arbitrary LAN daemon. Apple’s background execution model is constrained by power, performance, privacy, and specific background modes. Background App Refresh launches are opportunistic, frequency depends on user behavior, and apps often get only a short execution window.

Widgets are also not continuously running mini-apps. Apple’s WidgetKit model uses timeline entries, and visible widget code is not just running live on the Home Screen. Interactive widgets use App Intents through controls like buttons and toggles.

For remote widget updates, Apple describes APNs-based widget pushes, but those updates are budgeted, opportunistic, and not a replacement for urgent user notifications. Apple recommends user notifications for urgent updates and Live Activities for frequent, time-bounded updates.

There is also an important self-hosting constraint: ntfy’s iOS docs explain that instant iOS notifications require a central APNs-connected server; purely self-hosted iOS push has to work around Apple’s background restrictions, otherwise delivery may be delayed substantially.

So the product cannot honestly promise “free interaction with the phone” in an unconstrained sense. It can promise a strong subset:

1. actionable notifications,
2. widget actions,
3. Shortcuts/App Intents,
4. Live Activities for ongoing jobs,
5. secure API calls to homelab services,
6. APNs-backed wakeups with local payload fetching,
7. optional Tailscale/WireGuard/local-network operation.

**Sources:**

- [Apple WWDC 2019: Advances in App Background Execution](https://developer.apple.com/videos/play/wwdc2019/707/)
- [Apple WWDC 2023: Bring widgets to new places](https://developer.apple.com/videos/play/wwdc2023/10028/)
- [Apple WWDC 2025: Update widgets with WidgetKit push notifications](https://developer.apple.com/videos/play/wwdc2025/278/)
- [ntfy self-hosted iOS push notes](https://docs.ntfy.sh/config/)

## Build recommendation

Build it only if your product is **not** “another API widget app.” The defensible product is:

> **A programmable homelab operations console for iOS.**

The differentiators should be the following.

### 1. Self-hosted bridge container

Run a small Docker container in the homelab:

```text
homelab-bridge
  /events        receive events from scripts/services
  /notify        send actionable notifications to iOS
  /widgets       expose typed widget data
  /actions       receive action callbacks
  /schema        publish available cards/actions
  /audit         record who tapped what, when, and result
```

This avoids making every widget know how to talk directly to every internal service.

### 2. Config-as-code

Let users define widgets, notifications, and actions in YAML or JSON:

```yaml
widgets:
  - id: proxmox_cpu
    title: Proxmox CPU
    kind: metric
    source:
      method: GET
      url: https://pve.local/api2/json/nodes/pve/status
      auth: keychain:proxmox_token
    value: $.data.cpu
    format: percent
    refresh: opportunistic

notifications:
  - id: zfs_degraded
    title: ZFS pool degraded
    body: "{{ pool }} has {{ degraded_devices }} degraded devices"
    actions:
      - id: open_truenas
        title: Open TrueNAS
        kind: url
      - id: run_scrub
        title: Start scrub
        kind: api_call
        method: POST
        url: https://bridge.local/actions/zfs/scrub
```

HyperDash appears to target configurable API widgets; your version should target reproducible, developer-owned configurations.

### 3. First-class homelab templates

Ship templates for:

- Proxmox
- TrueNAS
- Unraid
- Docker / Compose
- Kubernetes
- Uptime Kuma
- Prometheus
- Grafana
- Home Assistant
- Tailscale
- Pi-hole / AdGuard Home
- Synology / QNAP
- generic REST, GraphQL, MQTT, WebSocket-to-bridge

This is where you can beat generic API-widget apps.

### 4. Bidirectional action semantics

Do not just send notifications. Define reliable action semantics:

```text
event_id
notification_id
action_id
actor_device_id
timestamp
idempotency_key
status: pending | accepted | failed | timed_out
result_payload
```

That gives you something Pushcut/Pushover-style tools usually do not expose as a homelab operations layer.

### 5. Security model

Use:

- iOS Keychain for secrets,
- per-widget/action permission scopes,
- optional mTLS,
- Tailscale/WireGuard/local HTTPS,
- signed action callbacks,
- audit logs,
- no plaintext secrets in widget configs,
- APNs relay carrying only opaque event IDs, with payload fetched from the user’s bridge when possible.

The APNs relay is almost unavoidable for fast iOS notifications unless you rely on an existing service or accept delayed polling. ntfy’s iOS documentation is a useful warning here.

## Suggested MVP

A strong MVP would include:

1. iOS app with configurable cards.
2. WidgetKit extension for metric/status/action widgets.
3. Notification extension with action buttons.
4. App Intents and Shortcuts integration.
5. Homelab bridge Docker container.
6. YAML/JSON import-export.
7. Templates for Proxmox, Docker, Uptime Kuma, Prometheus, and Home Assistant.
8. Push path: script → bridge → APNs/event wakeup → iOS notification.
9. Action path: notification/widget tap → App Intent → bridge callback → service action → audit result.

The most important validation experiments are notification latency, action callback success rate, widget staleness, VPN/Tailscale behavior, offline retry behavior, and whether users can configure common homelab APIs without writing too much glue code.

## Bottom line

The base idea **already exists** through HyperDash, AnyMetrics/API Widgets, Scriptable, Pushcut, ntfy, Pushover, Simplepush/PushBack, Home Assistant, and several homelab-specific apps.

The promising product is narrower and deeper:

> **A local-first, programmable iOS homelab cockpit with config-as-code widgets, actionable notifications, a self-hosted bridge, typed integrations, and reliable action/audit semantics.**

That is meaningfully different from the existing apps found in this research.
