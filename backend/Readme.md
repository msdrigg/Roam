# Discord Support Chat for Roam

- Cloudflare Workers REST API
  - Route to get last 100 messages from a channel, paginated, filtered by last message received
  - Route to post a message to a channel (that already exists)
  - Route to create a channel with a start message and return channel ID
- Cloudflare Workers Cron Job
  - Check for new messages every 10 seconds
  - Send APNS notification to device for every new message
  - Store APNS token in cloudflare KV storage based off the thread ID on the thread that gets used
  - Store "Last notified message ID" in cloudflare KV. This is used to ensure only pulling latest data
