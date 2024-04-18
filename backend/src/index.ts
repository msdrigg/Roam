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

type MessageRequest = {
	title: string;
	content: string;
	userId: string;
	apnsToken: string | null;
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

		if (pathSegments[0] === "messages") {
			let userId = pathSegments[1];
			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}
			let threadId = await env.ROAM_KV.get(`threadId:${userId}`);

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			if (!threadId) {
				return new Response("Not found", { status: 404 });
			}

			let messages = (await discordClient.getMessagesInThread(threadId, after))
				.filter((message) => message.content && message.type in [0, 19, 20, 21] && !message.content.startsWith("!HiddenMessage"));

			return new Response(JSON.stringify(messages), { status: 200 });
		}

		if (pathSegments[0] === "new-message") {
			let {
				title,
				content,
				apnsToken,
				userId,
			} = await request.json() as MessageRequest;
			console.log("Handling new message request", title, content, apnsToken, userId);

			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}

			let existingThreadId = await env.ROAM_KV.get(`threadId:${userId}`);
			console.log(`Existing thread ID: ${existingThreadId}`)

			if (apnsToken && existingThreadId) {
				await env.ROAM_KV.put(`apnsToken:${existingThreadId}`, apnsToken);
				await env.ROAM_KV.put(`apnsToken:${userId}`, apnsToken);
			}

			if (existingThreadId) {
				if (content) {
					await discordClient.sendMessage(existingThreadId, content);
				}

				return new Response("OK", { status: 200 });
			}

			let threadId = await discordClient.createThread(title, content);
			await env.ROAM_KV.put(`threadId:${userId}`, threadId);

			if (apnsToken) {
				await env.ROAM_KV.put(`apnsToken:${existingThreadId}`, apnsToken);
				await env.ROAM_KV.put(`apnsToken:${userId}`, apnsToken);
			}


			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "upload-diagnostics") {
			let diagnosticKey = pathSegments[1];
			if (!diagnosticKey) {
				return new Response("Bad request", { status: 400 });
			}

			let data = await request.arrayBuffer();
			console.log(`Uploading diagnostic data for key: ${diagnosticKey}`);
			await env.ROAM_DIAGNOSTIC_BUCKET.put(diagnosticKey, data, {
				httpMetadata: {
					contentType: "application/json"
				}
			});

			return new Response("OK", { status: 200 });
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

			let messages = (await discordClient.getMessagesInThread(thread.id, latestMessageId))
				.filter((message) => message.content && message.type in [0, 19, 20, 21] && !message.content.startsWith("!HiddenMessage"));

			for (let message of messages) {
				if (message.author.id === env.DISCORD_BOT_ID) {
					console.log("Skipping message from bot");
					// Don't notify on messages from the bot
					continue;
				}
				try {
					console.log(`Sending push notification for message: ${message.content} to ${apnsToken} with bundle ID ${env.ROAM_BUNDLE_ID}`)
					await sendPushNotification("Message from roam", message.content, apnsKey, apnsToken, env.ROAM_BUNDLE_ID);
				} catch (e) {
					console.error(`Error sending push notification: ${e}`);
				}
			}
		}
	},
} satisfies ExportedHandler<Env>;
