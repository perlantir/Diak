# Diak Connector Setup Dogfood — 20260510-114012

Result: BLOCKED

- Base URL: `http://127.0.0.1:18766`
- Bridge mode: `production_bridge`
- Runtime: `hermes-agent`
- Connector tested: `conn-notion`
- Setup response HTTP: `200`
- Setup state: `configuration_required`
- Setup URL present: `False`

Verdict detail:
- The Diak production bridge connector endpoints are reachable and return typed connector catalog JSON.
- Live provider OAuth setup is blocked because connector provider setup env is not configured in this shell (`COMPOSIO_API_KEY` and `DIAK_CONNECTOR_SETUP_URL_TEMPLATE` are missing).
- This is expected safe behavior; the bridge returns `configuration_required` rather than pretending OAuth succeeded.

Evidence files:
- `version.json`
- `connectors.json`
- `connectors_conn-notion.json`
- `conn-notion_setup.json`
- `bridge.log`
