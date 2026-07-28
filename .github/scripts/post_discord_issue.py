#!/usr/bin/env python3
"""Post a GitHub issue status update to a Discord channel.

Reads issue metadata from environment variables (populated by the workflow from
the `github.event.issue` context) and posts a formatted embed to a Discord
channel via an incoming webhook.

Environment variables:
  DISCORD_ISSUE_WEBHOOK_URL (required) Discord channel webhook URL.
  DISCORD_BOT_TOKEN         (optional) Bot token. If set, the posted message is
                            crossposted (published) to servers following this
                            announcement channel. The bot must be in the server
                            with View Channel + Manage Messages on this channel.
  ISSUE_ACTION              opened | reopened | closed | edited ...
  ISSUE_NUMBER              Issue number, e.g. "264".
  ISSUE_TITLE               Issue title.
  ISSUE_URL                 HTML URL of the issue.
  ISSUE_AUTHOR              Login of the user who opened the issue.
  ISSUE_LABELS              Comma-separated label names (optional).
  ISSUE_STATE_REASON        completed | not_planned | reopened (optional).
  CHANGED_LABEL             Label name for labeled/unlabeled events (optional).
  CHANGED_ASSIGNEE          Login for assigned/unassigned events (optional).

The issue body is read from stdin (may be empty).
"""
import os
import sys
import json
import urllib.request
import urllib.error

# Discord embed colors per action.
COLORS = {
    "opened": 3066993,      # green
    "reopened": 15844367,   # gold
    "closed": 10038562,     # dark red
    "edited": 3447003,      # blue
    "labeled": 5793266,     # blurple
    "unlabeled": 9807270,   # grey
    "assigned": 1752220,    # teal
    "unassigned": 9807270,  # grey
    "default": 3447003,     # blue
}

# Emoji + verb per action for the embed title.
TITLES = {
    "opened": "🐛 Issue Opened",
    "reopened": "🔄 Issue Reopened",
    "closed": "✅ Issue Closed",
    "edited": "✏️ Issue Updated",
    "labeled": "🏷️ Issue Labeled",
    "unlabeled": "🏷️ Issue Unlabeled",
    "assigned": "👤 Issue Assigned",
    "unassigned": "👤 Issue Unassigned",
}


def crosspost(channel_id, message_id, token):
    """Publish an announcement-channel message to following servers.

    Requires a bot token with Manage Messages on the channel (the message was
    authored by the webhook, not the bot). Failure here is non-fatal: the
    message is already posted, it just won't reach follower servers.
    """
    api_url = (
        f"https://discord.com/api/v10/channels/{channel_id}"
        f"/messages/{message_id}/crosspost"
    )
    req = urllib.request.Request(api_url, method="POST", data=b"")
    req.add_header("Authorization", f"Bot {token}")
    req.add_header("Content-Type", "application/json")
    req.add_header(
        "User-Agent",
        "Tracelet-GitHubAction (https://github.com/Ikolvi/Tracelet, 1.0.0)",
    )
    try:
        with urllib.request.urlopen(req) as response:
            if response.status in (200, 204):
                print(f"Published message {message_id} to followers.")
                return
            print(f"Crosspost returned status {response.status}.", file=sys.stderr)
    except urllib.error.HTTPError as e:
        print(f"HTTPError crossposting: {e.code} {e.reason}", file=sys.stderr)
        print(e.read().decode("utf-8"), file=sys.stderr)
    except urllib.error.URLError as e:
        print(f"URLError crossposting: {e.reason}", file=sys.stderr)


def main():
    webhook_url = os.environ.get("DISCORD_ISSUE_WEBHOOK_URL")
    bot_token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()

    if not webhook_url:
        print("Error: DISCORD_ISSUE_WEBHOOK_URL environment variable is not set.", file=sys.stderr)
        sys.exit(1)

    action = os.environ.get("ISSUE_ACTION", "opened").lower()
    number = os.environ.get("ISSUE_NUMBER", "?")
    title = os.environ.get("ISSUE_TITLE", "Untitled issue")
    url = os.environ.get("ISSUE_URL", "")
    author = os.environ.get("ISSUE_AUTHOR", "unknown")
    labels_raw = os.environ.get("ISSUE_LABELS", "").strip()
    state_reason = os.environ.get("ISSUE_STATE_REASON", "").strip()
    changed_label = os.environ.get("CHANGED_LABEL", "").strip()
    changed_assignee = os.environ.get("CHANGED_ASSIGNEE", "").strip()

    body = sys.stdin.read().strip()

    # Discord embed description limit is 4096 chars. Keep a short preview only —
    # this is a status feed, not a mirror of the full issue body.
    if action == "opened" and body:
        preview = body if len(body) <= 500 else body[:497] + "..."
    else:
        preview = ""

    embed_title = TITLES.get(action, f"Issue {action.capitalize()}")

    # For closed issues, note whether it was completed or not planned.
    status_note = ""
    if action == "closed":
        if state_reason == "not_planned":
            status_note = " (not planned)"
        elif state_reason == "completed":
            status_note = " (completed)"

    fields = [
        {"name": "Issue", "value": f"#{number}", "inline": True},
        {"name": "Author", "value": author, "inline": True},
    ]

    # Highlight the specific change that triggered this event.
    if action in ("labeled", "unlabeled") and changed_label:
        verb = "Added" if action == "labeled" else "Removed"
        fields.append({"name": f"Label {verb}", "value": changed_label, "inline": True})
    if action in ("assigned", "unassigned") and changed_assignee:
        verb = "Assigned to" if action == "assigned" else "Unassigned"
        fields.append({"name": verb, "value": changed_assignee, "inline": True})

    if labels_raw:
        fields.append({"name": "Current Labels", "value": labels_raw, "inline": False})

    embed = {
        "title": f"{embed_title}{status_note}: {title}",
        "color": COLORS.get(action, COLORS["default"]),
        "fields": fields,
        "footer": {"text": "Tracelet Issue Tracker"},
    }
    if url:
        embed["url"] = url
    if preview:
        embed["description"] = preview

    payload = {"embeds": [embed]}

    # When a bot token is available we ask the webhook to return the created
    # message (?wait=true) so we can crosspost it to follower servers. Without a
    # token there's nothing to publish, so the default fire-and-forget is fine.
    post_url = webhook_url
    want_message = bool(bot_token)
    if want_message:
        sep = "&" if "?" in post_url else "?"
        post_url = f"{post_url}{sep}wait=true"

    req = urllib.request.Request(post_url, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header(
        "User-Agent",
        "Tracelet-GitHubAction (https://github.com/Ikolvi/Tracelet, 1.0.0)",
    )

    data = json.dumps(payload).encode("utf-8")

    try:
        with urllib.request.urlopen(req, data=data) as response:
            # Webhooks return 204 No Content normally, or 200 with the message
            # body when ?wait=true is set.
            if response.status not in (200, 201, 204):
                print(f"Failed to post to Discord. Status: {response.status}", file=sys.stderr)
                sys.exit(1)
            print(f"Successfully posted issue #{number} ({action}) to Discord.")

            if want_message and response.status == 200:
                try:
                    msg = json.loads(response.read().decode("utf-8"))
                    channel_id = msg.get("channel_id")
                    message_id = msg.get("id")
                except (ValueError, AttributeError):
                    channel_id = message_id = None
                if channel_id and message_id:
                    crosspost(channel_id, message_id, bot_token)
                else:
                    print("Could not read message id; skipping publish.", file=sys.stderr)
    except urllib.error.HTTPError as e:
        print(f"HTTPError posting to Discord: {e.code} {e.reason}", file=sys.stderr)
        print(e.read().decode("utf-8"), file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"URLError posting to Discord: {e.reason}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
