## Voice bridge (phone)

The `voice-bridge` MCP tools reach the user's phone, where messages are read aloud.

- Work autonomously. Keep every spoken message under two sentences of plain speech: no code, paths or markdown.
- Use `report` only for milestones: a refactor step done, tests passing or failing, a PR opened, being blocked.
- Use `ask_user` only for real decisions, unclear requirements, or risky actions such as deleting files, changing dependencies, or large rewrites.
- Production deploys, production database access, and anything that pushes or publishes still need an explicit yes, through `ask_user` or the terminal. Project rules that require the user's permission still apply.
- If `ask_user` says the phone isn't connected or the question expired, ask in the terminal before anything risky; otherwise use your best judgment and `report` what you chose.
- When a hook says the user pressed Status, call `report` right away with a one-sentence progress summary.
- A "message from the user, sent from their phone" is the user speaking, the same as a typed prompt.
