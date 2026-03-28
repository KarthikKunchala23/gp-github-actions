import os
import sys
import json


def validate_commit():
    event_path = os.getenv("GITHUB_EVENT_PATH")

    if not event_path:
        print("GITHUB_EVENT_PATH not set")
        sys.exit(1)

    with open(event_path, "r") as f:
        event = json.load(f)

    # Handle push and PR events
    commit_message = ""

    if "head_commit" in event:
        commit_message = event.get("head_commit", {}).get("message", "")
    elif "pull_request" in event:
        commit_message = event.get("pull_request", {}).get("title", "")

    print(f"Commit message: {commit_message}")

    output_path = os.getenv("GITHUB_OUTPUT")

    if not output_path:
        print("GITHUB_OUTPUT not set")
        sys.exit(1)

    if "[deploy-prod]" in commit_message.lower():
        print("Commit is valid")
        with open(output_path, "a") as f:
            f.write("allow_apply=true\n")
    else:
        print("Commit is invalid")
        with open(output_path, "a") as f:
            f.write("allow_apply=false\n")

    sys.exit(0)


if __name__ == "__main__":
    validate_commit()