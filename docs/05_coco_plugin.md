# Install the demo as a CoCo Desktop plugin

This repo is a CoCo Desktop plugin, named `riv-lakehouse-demo`. Its manifest is `.cortex-plugin/plugin.json`, and it contains one skill, `riv-lakehouse-demo`. Install it once; then CoCo can set up, run and tear down the demo from chat.

The skill runs files from the rest of the repo (`sql/`, `aws/`, `tests/render.py`), so install the **whole repo** as the plugin, not just the `skills/` folder.

## Before you start

- **CoCo Desktop** is installed and connected to your Snowflake account. You need ACCOUNTADMIN in that account.
- **AWS CLI v2**, with a `sesandbox` profile for the SE Sandbox (account `484577546576`). The skill checks this and can walk you through setting it up; see [skills/riv-lakehouse-demo/references/aws-cli-setup.md](../skills/riv-lakehouse-demo/references/aws-cli-setup.md).
- **`python3`** (the macOS built-in one works) and **`git`**.

## Option A: local folder (recommended)

1. Clone the repo:
   ```bash
   git clone https://github.com/sfc-gh-aengelbrecht/riv2026datalakedemo.git ~/Documents/GitHub/riv2026datalakedemo
   ```
2. In CoCo Desktop, click **Agent Settings** in the left sidebar, then choose the **Plugins** category.
3. Click **+** and choose **Add Local Plugin**.
4. Select the repo root folder, the one that contains `.cortex-plugin/`, for example `~/Documents/GitHub/riv2026datalakedemo`.
5. Check that the `riv-lakehouse-demo` card shows up and its switch is on. The skill is listed under **Agent Settings, then Skills**.

A local plugin is registered by reference: CoCo uses the folder where it is and copies nothing. To get updates, run `git pull` in the folder; CoCo picks up the changes automatically.

## Option B: from GitHub

1. In CoCo Desktop, open **Agent Settings, then Plugins**, click **+** and choose **Add from GitHub**.
2. Enter `sfc-gh-aengelbrecht/riv2026datalakedemo#main`.
3. CoCo clones the repo into `~/.snowflake/cortex/plugins/` and registers it. Use **Sync** (the circular-arrow button on the plugin's detail page) to pull updates.

Your GitHub account needs read access to the repo.

Sync overwrites the install folder, and that includes the skill's per-user working files in `.riv-demo/` (your saved names and generated SQL). Those are only needed again for teardown. If you'll need them, use Option A instead.

## Option C: ask CoCo

In the chat panel, type one of these, and the bundled installer skill does the rest:

- `install local plugin from ~/Documents/GitHub/riv2026datalakedemo`
- `install plugin from github sfc-gh-aengelbrecht/riv2026datalakedemo`

## Use it

Start a new chat and either type `/riv-lakehouse-demo` (also listed as `/riv-lakehouse-demo:riv-lakehouse-demo`), or just ask in plain language:

| Ask | What happens |
|---|---|
| "Set up the RIV lakehouse demo" | Full setup: ACCOUNTADMIN check, sandbox check, your names, the AWS bucket and role, the Snowflake objects, and the agent added to CoWork |
| "Is the RIV Lambda running?" | Runs `lambda_status.sh` |
| "Start the RIV micro-batch" | Checks the status first, then starts the Lambda only if no run is active |
| "Stop the RIV micro-batch" | Sets the stop flag |
| "Tear down my RIV demo" | Removes your agent, the Snowflake objects, and your AWS role and bucket (after you confirm) |

The demo script and architecture diagram are in [skills/riv-lakehouse-demo/references/demo-guide.md](../skills/riv-lakehouse-demo/references/demo-guide.md).

## Troubleshooting the install

- **The plugin doesn't appear.** Make sure you selected the repo root, the folder that contains `.cortex-plugin/plugin.json`, not `skills/`. Then click the refresh button in the Plugins toolbar.
- **The skill doesn't trigger.** Check that the plugin's switch is on, then invoke it explicitly with `/riv-lakehouse-demo`.
- **The GitHub import fails.** Check your GitHub access to the repo, or use Option A.
- **Scripts fail with "permission denied".** Run them as `bash script.sh`. The skill does this already; `chmod` may be blocked by org policy.
