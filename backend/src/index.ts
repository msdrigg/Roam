import { APNSAuthKey, sendPushNotification } from "./apns";
import DiscordClient from "./discord";

export interface Env {
	ROAM_KV: KVNamespace;
	ROAM_DIAGNOSTIC_BUCKET: R2Bucket;

	// Secrets
	DISCORD_TOKEN: string;
	DISCORD_HELP_CHANNEL: string;
	DISCORD_BOT_ID: string;
	DISCORD_GUILD_ID: string;

	APNS_KEY_ID: string;
	APNS_TEAM_ID: string;
	APNS_PRIVATE_KEY: string;

	API_KEY: string;

	// Vars
	ROAM_BUNDLE_ID: string;
}

type ThreadCreateRequest = {
	title: string;
	content: string;
	apnsToken: string | null;
}

type MessageCreateRequest = {
	chatId: string;
	content: string
}

export default {
	async fetch(request, env, ctx): Promise<Response> {
		let pathSegments = new URL(request.url).pathname.split("/").filter(Boolean);
		let apiKeyHeader = request.headers.get("x-api-key");
		if (apiKeyHeader !== env.API_KEY) {
			return new Response("Unauthorized", { status: 401 });
		}

		let discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);

		if (pathSegments.length === 0) {
			return new Response("Hello, world!", { status: 200 });
		}

		if (pathSegments[0] === "latestMessageId") {
			let latestMessageId = await env.ROAM_KV.get("latestMessageId");
			return new Response(latestMessageId || "0", { status: 200 });
		}

		if (pathSegments[0] === "threads") {
			let threads = await discordClient.getActiveThreadsUpdatedSince(null);

			return new Response(JSON.stringify(threads), { status: 200 });
		}

		if (pathSegments[0] === "messages") {
			let chatId = pathSegments[1];
			let threadId = await env.ROAM_KV.get(`threadId:${chatId}`);

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			if (!threadId) {
				return new Response("Not found", { status: 404 });
			}

			let messages = await discordClient.getMessagesInThread(threadId, after);

			return new Response(JSON.stringify(messages), { status: 200 });
		}

		if (pathSegments[0] === "new-thread") {
			let {
				title,
				content,
				apnsToken
			} = await request.json() as ThreadCreateRequest;

			let threadId = await discordClient.createThread(title, content);
			let uniqueId = crypto.randomUUID();
			await env.ROAM_KV.put(`threadId:${uniqueId}`, threadId);

			if (apnsToken) {
				await env.ROAM_KV.put(`apnsToken:${threadId}`, apnsToken);
			}

			return new Response(JSON.stringify({ chatId: uniqueId }), { status: 200 });
		}

		if (pathSegments[0] === "new-message") {
			let {
				chatId,
				content
			} = await request.json() as MessageCreateRequest;

			let threadId = await env.ROAM_KV.get(`threadId:${chatId}`);

			if (!threadId) {
				return new Response("Not found", { status: 404 });
			}

			await discordClient.sendMessage(threadId, content);
			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "upload-diagnostics") {
			let diagnosticKey = pathSegments[1];
			if (!diagnosticKey) {
				return new Response("Bad request", { status: 400 });
			}

			env.ROAM_DIAGNOSTIC_BUCKET.put(diagnosticKey, await request.arrayBuffer());
		}

		return new Response("Not found", { status: 404 });
	},

	async scheduled(event, env, ctx) {
		console.log("Handling scheduled event")
		let discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);

		let latestMessageId = await env.ROAM_KV.get("latestMessageId");

		let threads = await discordClient.getActiveThreadsUpdatedSince(latestMessageId);

		let latestOverallMessageId = Math.max(latestMessageId ? parseInt(latestMessageId) : 0,
			...threads.map(thread => parseInt(thread.lastMessageId))
		);

		if (latestOverallMessageId > 0 && (!latestMessageId || latestOverallMessageId > parseInt(latestMessageId))) {
			console.log(`Found new messages since ${latestMessageId}`);

			await env.ROAM_KV.put("latestMessageId", latestOverallMessageId.toString());
		}

		let apnsKey: APNSAuthKey = {
			keyId: env.APNS_KEY_ID,
			teamId: env.APNS_TEAM_ID,
			privateKey: env.APNS_PRIVATE_KEY,
		}

		for (let thread of threads) {
			let apnsToken = await env.ROAM_KV.get(`apnsToken:${thread.id}`);
			if (!apnsToken) {
				console.log(`No APNS token found for thread ${thread.id}`);
				continue;
			} else {
				console.log(`APNS token ${apnsToken} found for thread ${thread.id}`);
			}

			let messages = await discordClient.getMessagesInThread(thread.id, latestMessageId);

			for (let message of messages) {
				if (message.author.id === env.DISCORD_BOT_ID) {
					console.log("Skipping message from bot");
					// Don't notify on messages from the bot
					continue;
				}
				try {
					await sendPushNotification("Message from roam", message.content, apnsKey, apnsToken, env.ROAM_BUNDLE_ID);
				} catch (e) {
					console.error(`Error sending push notification: ${e}`);
				}
			}
		}
	},
} satisfies ExportedHandler<Env>;
